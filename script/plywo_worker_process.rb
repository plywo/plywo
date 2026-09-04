#!/usr/bin/env ruby

require "json"

require File.join(Dir.pwd, "config/environment")

subscriber = nil

begin
  payload = JSON.parse(File.read(ENV.fetch("PLYWO_JOB_PAYLOAD")))
  output_path = ENV.fetch("PLYWO_WORKER_OUTPUT")
  expected_execution_id = payload.dig(Plywo::Rails::ActiveJobExecutionContext::CONTEXT_KEY, "plywo_execution_id").to_s
  expected_job_id = payload.fetch("job_id").to_s

  current_snapshot = lambda do
    {
      "execution_id" => Current.plywo_execution_id,
      "run_id" => Current.plywo_run_id,
      "subject" => Current.plywo_subject
    }
  end

  before = current_snapshot.call
  raise "Worker process inherited Plywo Current state" if before.values.any?
  raise "Worker process started inside a Plywo internal operation" if Plywo::Rails::InternalOperation.active?

  observed_execution_ids = []
  subscriber = ActiveSupport::Notifications.subscribe(Plywo::Rails::Evidence::OBSERVATION_EVENT_NAME) do |event|
    execution_id = event.payload[:execution_id]
    observed_execution_ids << execution_id.to_s if execution_id
  end

  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  ActiveJob::Base.execute(payload)
  elapsed_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000).round(1)

  after = current_snapshot.call
  work_item = PlywoExecutionWorkItem.find_by!(
    execution_id: expected_execution_id,
    kind: "active_job",
    work_id: expected_job_id
  )
  evidence = PlywoEvidenceEvent.where(execution_id: expected_execution_id, producer_id: expected_job_id).order(:id)

  raise "Worker did not restore the serialized Plywo execution context" unless observed_execution_ids.include?(expected_execution_id)
  raise "Worker did not complete its durable work item" unless work_item.status == "completed"
  raise "Worker did not persist correlated evidence" if evidence.empty?
  raise "Worker leaked Plywo Current state after execution" if after.values.any?

  report = {
    "worker_pid" => Process.pid,
    "parent_pid" => Process.ppid,
    "current_before" => before,
    "current_after" => after,
    "expected_execution_id" => expected_execution_id,
    "observed_execution_ids" => observed_execution_ids.uniq,
    "job_id" => expected_job_id,
    "work_item_status" => work_item.status,
    "evidence_signals" => evidence.map(&:signal),
    "worker_elapsed_ms" => elapsed_ms
  }

  File.write(output_path, JSON.pretty_generate(report))
  puts JSON.pretty_generate(report)
ensure
  ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  Current.reset
end
