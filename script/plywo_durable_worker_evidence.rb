#!/usr/bin/env ruby

require "json"
require "securerandom"

require File.join(Dir.pwd, "config/environment")

execution_id = SecureRandom.uuid
run_id = "durable-worker-#{SecureRandom.hex(4)}"
serialized_job = nil
origin_collector = Plywo::Rails::EvidenceCollector.new(execution_id:)

origin_measurements = origin_collector.capture do
  Current.set(
    plywo_execution_id: execution_id,
    plywo_run_id: run_id,
    plywo_subject: "durable-worker-proof"
  ) do
    serialized_job = DemoAsyncEvidenceJob.new.serialize
  end
end

Current.reset
raise "Plywo execution context leaked after origin lifecycle" if Current.plywo_execution_id

ActiveJob::Base.deserialize(serialized_job).perform_now

records = PlywoEvidenceEvent.where(execution_id:).order(:id).to_a
signals = records.map(&:signal)
expected_signals = %w[sql_queries emails http_requests]

raise "Expected #{expected_signals.inspect}, got #{signals.inspect}" unless signals == expected_signals
raise "Expected one producer kind" unless records.all? { |record| record.producer_kind == "active_job" }
raise "Expected DemoAsyncEvidenceJob producer" unless records.all? { |record| record.producer_name == "DemoAsyncEvidenceJob" }
raise "Expected propagated run id" unless records.all? { |record| record.run_id == run_id }
raise "Expected propagated subject" unless records.all? { |record| record.subject == "durable-worker-proof" }
raise "Expected application source attribution" unless records.all? { |record| record.path == "app/jobs/demo_async_evidence_job.rb" }

payload = {
  execution_id:,
  run_id:,
  origin_collector_closed_before_worker: true,
  origin_measurements:,
  current_cleared_before_worker: true,
  persisted_events: records.map do |record|
    {
      signal: record.signal,
      path: record.path,
      line: record.start_line,
      confidence: record.confidence,
      producer_kind: record.producer_kind,
      producer_name: record.producer_name,
      producer_id: record.producer_id
    }
  end
}

puts JSON.pretty_generate(payload)
