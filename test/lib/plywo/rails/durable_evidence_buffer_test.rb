require "test_helper"

class PlywoDurableEvidenceProbeJob < ApplicationJob
  def perform
    ApplicationRecord.connection.select_value("SELECT 1")
    DemoMailer.notification(Current.plywo_execution_id).deliver_now
    Net::HTTP.get(URI.parse(Plywo::Demo::LoopbackHttpServer.url))
  end
end

class PlywoFailingEvidenceJob < ApplicationJob
  def perform
    ApplicationRecord.connection.select_value("SELECT 1")
    raise "durable evidence proof failure"
  end
end

class PlywoRailsDurableEvidenceBufferTest < ActiveSupport::TestCase
  RUNTIME_SIGNALS = %w[worker_wall_ms worker_process_cpu_ms worker_thread_cpu_ms].freeze

  setup do
    Current.reset
    PlywoEvidenceEvent.delete_all
    PlywoExecutionWorkItem.delete_all
  end

  teardown do
    Current.reset
    PlywoEvidenceEvent.delete_all
    PlywoExecutionWorkItem.delete_all
  end

  test "persists worker evidence after the originating collector has closed" do
    execution_id = "durable-execution-123"
    run_id = "durable-run-456"
    serialized_job = nil
    origin_collector = Plywo::Rails::EvidenceCollector.new(execution_id:)

    origin_collector.capture do
      Current.set(
        plywo_execution_id: execution_id,
        plywo_run_id: run_id,
        plywo_subject: "candidate"
      ) do
        serialized_job = PlywoDurableEvidenceProbeJob.new.serialize
      end
    end

    Current.reset
    assert_nil Current.plywo_execution_id

    job = ActiveJob::Base.deserialize(serialized_job)
    job.perform_now

    records = PlywoEvidenceEvent.where(execution_id:).order(:id).to_a
    product_records = records.reject { |record| RUNTIME_SIGNALS.include?(record.signal) }
    runtime_records = records.select { |record| RUNTIME_SIGNALS.include?(record.signal) }

    assert_equal %w[sql_queries emails http_requests], product_records.map(&:signal)
    assert_equal RUNTIME_SIGNALS, runtime_records.map(&:signal)
    assert records.all? { |record| record.run_id == run_id }
    assert records.all? { |record| record.subject == "candidate" }
    assert records.all? { |record| record.producer_kind == "active_job" }
    assert records.all? { |record| record.producer_name == "PlywoDurableEvidenceProbeJob" }
    assert records.all? { |record| record.producer_id.present? }
    assert product_records.all? { |record| record.path == "test/lib/plywo/rails/durable_evidence_buffer_test.rb" }
    assert product_records.all? { |record| record.confidence == "runtime" }
    assert runtime_records.all? { |record| record.payload.fetch("value") >= 0.0 }
    assert runtime_records.all? { |record| record.confidence == "runtime" }

    work_item = PlywoExecutionWorkItem.find_by!(execution_id:, work_id: job.job_id)
    assert_equal "completed", work_item.status
    assert work_item.terminal?
    assert Plywo::Rails::ExecutionWorkLifecycle.quiescent?(execution_id:)
    assert_nil Current.plywo_execution_id
  end

  test "persists partial evidence, runtime probes and marks work failed when the worker raises" do
    execution_id = "failing-execution-123"
    serialized_job = Current.set(
      plywo_execution_id: execution_id,
      plywo_run_id: "failing-run-456",
      plywo_subject: "candidate"
    ) do
      PlywoFailingEvidenceJob.new.serialize
    end

    Current.reset
    job = ActiveJob::Base.deserialize(serialized_job)

    error = assert_raises(RuntimeError) { job.perform_now }
    assert_equal "durable evidence proof failure", error.message

    records = PlywoEvidenceEvent.where(execution_id:).order(:id).to_a
    product_records = records.reject { |record| RUNTIME_SIGNALS.include?(record.signal) }
    runtime_records = records.select { |record| RUNTIME_SIGNALS.include?(record.signal) }

    assert_equal %w[sql_queries errors], product_records.map(&:signal)
    assert_equal RUNTIME_SIGNALS, runtime_records.map(&:signal)
    assert_equal "PlywoFailingEvidenceJob", product_records.first.producer_name
    assert_equal "runtime", product_records.first.confidence
    assert_equal({ "error_class" => "RuntimeError" }, product_records.last.payload)
    assert runtime_records.all? { |record| record.payload.fetch("value") >= 0.0 }

    work_item = PlywoExecutionWorkItem.find_by!(execution_id:, work_id: job.job_id)
    assert_equal "failed", work_item.status
    assert_equal "RuntimeError", work_item.error_class
    assert_not_nil work_item.started_at
    assert_not_nil work_item.finished_at
    assert work_item.terminal?
    assert Plywo::Rails::ExecutionWorkLifecycle.quiescent?(execution_id:)
    assert_nil Current.plywo_execution_id
  end
end
