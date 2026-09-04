require "test_helper"

class PlywoRealQueueProbeJob < ApplicationJob
  CONTEXT_EVENT = "plywo.real_queue_probe"

  def perform
    ActiveSupport::Notifications.instrument(
      CONTEXT_EVENT,
      execution_id: Current.plywo_execution_id,
      run_id: Current.plywo_run_id,
      subject: Current.plywo_subject
    )
    ApplicationRecord.connection.select_value("SELECT 1")
  end
end

class PlywoRailsTestQueueExecutionTest < ActiveSupport::TestCase
  setup do
    Current.reset
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
    PlywoEvidenceEvent.delete_all
  end

  teardown do
    Current.reset
    ActiveJob::Base.queue_adapter.enqueued_jobs.clear
    ActiveJob::Base.queue_adapter.performed_jobs.clear
    PlywoEvidenceEvent.delete_all
  end

  test "executes the actual queued payload after ambient context is cleared" do
    execution_id = "real-queue-execution-123"
    observed_context = nil
    subscriber = ActiveSupport::Notifications.subscribe(PlywoRealQueueProbeJob::CONTEXT_EVENT) do |event|
      observed_context = event.payload
    end

    Current.set(
      plywo_execution_id: execution_id,
      plywo_run_id: "real-queue-run-456",
      plywo_subject: "candidate"
    ) do
      PlywoRealQueueProbeJob.perform_later
    end

    queued = ActiveJob::Base.queue_adapter.enqueued_jobs.first
    serialized_context = queued.fetch(Plywo::Rails::ActiveJobExecutionContext::CONTEXT_KEY)
    queued_job_id = queued.fetch("job_id")

    Current.reset
    assert_nil Current.plywo_execution_id

    executions = Plywo::Rails::TestQueueExecution.drain(execution_id:)

    assert_equal 1, executions.size
    assert_equal "PlywoRealQueueProbeJob", executions.first.fetch("job_class")
    assert_equal queued_job_id, executions.first.fetch("job_id")
    assert_equal "application_enqueue", executions.first.fetch("source")
    assert_equal execution_id, serialized_context.fetch("plywo_execution_id")
    assert_equal execution_id, observed_context.fetch(:execution_id)
    assert_equal "real-queue-run-456", observed_context.fetch(:run_id)
    assert_equal "candidate", observed_context.fetch(:subject)
    assert_empty ActiveJob::Base.queue_adapter.enqueued_jobs

    record = PlywoEvidenceEvent.find_by!(execution_id:, signal: "sql_queries")
    assert_equal "PlywoRealQueueProbeJob", record.producer_name
    assert_equal queued_job_id, record.producer_id
    assert_equal "test/lib/plywo/rails/test_queue_execution_test.rb", record.path
    assert_nil Current.plywo_execution_id
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end

  test "leaves jobs from other executions queued" do
    Current.set(plywo_execution_id: "execution-a") { DemoNotificationJob.perform_later }
    Current.set(plywo_execution_id: "execution-b") { DemoNotificationJob.perform_later }

    executions = Plywo::Rails::TestQueueExecution.drain(execution_id: "execution-a")

    assert_equal 1, executions.size
    assert_equal "execution-a", executions.first.fetch("execution_id")
    assert_equal 1, ActiveJob::Base.queue_adapter.enqueued_jobs.size
    remaining_context = ActiveJob::Base.queue_adapter.enqueued_jobs.first.fetch(
      Plywo::Rails::ActiveJobExecutionContext::CONTEXT_KEY
    )
    assert_equal "execution-b", remaining_context.fetch("plywo_execution_id")
  end
end
