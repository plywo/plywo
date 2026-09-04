#!/usr/bin/env ruby

require "json"
require "rack/mock"
require "securerandom"

SUBJECT_ROOT = Dir.pwd.freeze

require File.join(SUBJECT_ROOT, "config/environment")

unless defined?(Plywo::Rails::ExecutionQuiescence)
  require File.join(SUBJECT_ROOT, "lib/plywo/rails/execution_quiescence")
end

class PlywoSubjectCapture
  DEFAULT_PATH = "/__plywo/demo/behavior".freeze
  DEFAULT_SCENARIO_ID = "dogfood.git.behavior".freeze
  DEFAULT_START_TIMEOUT_SECONDS = 10.0
  DEFAULT_QUIESCENCE_TIMEOUT_SECONDS = 5.0
  DEFAULT_QUIET_PERIOD_SECONDS = 0.05

  def call
    warm_runtime
    reset_test_queue

    execution_id = SecureRandom.uuid
    async_execution = prepare_async_execution(execution_id:)
    async_execution&.start

    response = nil
    collector = Plywo::Rails::EvidenceCollector.new(execution_id:)
    measurements = collector.capture do
      response = request.post(path, headers(execution_id:, subject:))
    end
    passed = response.status.between?(200, 299)
    measurements["errors"] += 1 unless passed

    Current.reset
    async_result = drive_async_work(execution_id:, async_execution:)
    application_job_executions = async_result.fetch("executions")
    quiescence = async_result.fetch("quiescence")

    raise "Expected the application request to enqueue at least one correlated job" if application_job_executions.empty?

    async_correlation_confirmed = application_job_executions.all? do |job|
      job.fetch("execution_id") == execution_id &&
        job.fetch("run_id") == run_id &&
        job.fetch("subject") == subject &&
        job.fetch("source") == "application_enqueue"
    end
    raise "Application-enqueued job lost Plywo execution context" unless async_correlation_confirmed

    payload = {
      "id" => label,
      "execution_id" => execution_id,
      "run_id" => run_id,
      "scenario_id" => scenario_id,
      "subject" => subject,
      "ref" => label,
      "sha" => sha,
      "status" => passed ? "passed" : "failed",
      "http_status" => response.status,
      "correlation_confirmed" => response["X-Plywo-Execution-Id"] == execution_id,
      "async_correlation_confirmed" => async_correlation_confirmed,
      "measurements" => measurements,
      "attributions" => collector.respond_to?(:attributions) ? collector.attributions : {},
      "durable_observations" => durable_observations(execution_id:),
      "application_job_executions" => application_job_executions,
      "lifecycle" => {
        "foreground_collector_closed_before_worker" => true,
        "current_cleared_before_worker" => true,
        "worker_origin" => "application_enqueue",
        "async_transport" => async_result.fetch("transport"),
        "completion_source" => "durable_work_ledger",
        "quiescence" => quiescence
      }
    }

    File.write(ENV.fetch("PLYWO_OUTPUT"), JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload)
  ensure
    Current.reset
    async_execution&.stop
    reset_test_queue
  end

  private

  def warm_runtime
    ApplicationRecord.connection.select_value("SELECT 1")
    request.post(path, headers(execution_id: "warmup", subject: "warmup"))
  end

  def prepare_async_execution(execution_id:)
    return unless async_transport == "solid_queue"

    require_solid_queue_execution
    assert_subject_owned!(Plywo::Rails::SolidQueueExecution.instance_method(:start), "SolidQueueExecution")

    execution = Plywo::Rails::SolidQueueExecution.new(
      execution_id:,
      start_timeout_seconds: Float(
        ENV.fetch("PLYWO_SOLID_QUEUE_START_TIMEOUT_SECONDS", DEFAULT_START_TIMEOUT_SECONDS)
      ),
      quiescence_timeout_seconds: Float(
        ENV.fetch("PLYWO_QUIESCENCE_TIMEOUT_SECONDS", DEFAULT_QUIESCENCE_TIMEOUT_SECONDS)
      ),
      quiet_period_seconds: Float(ENV.fetch("PLYWO_QUIET_PERIOD_SECONDS", DEFAULT_QUIET_PERIOD_SECONDS))
    )

    install_solid_queue_diagnostics(execution)
    execution
  end

  def install_solid_queue_diagnostics(execution)
    return unless ENV["PLYWO_SOLID_QUEUE_DIAGNOSTICS"] == "1"
    return unless execution.respond_to?(:worker_log, true)

    diagnostics = Module.new do
      define_method(:stop) do
        log = send(:worker_log)
        super()
      ensure
        warn "Plywo Solid Queue worker log:\n#{log}" if log && !log.empty?
      end
    end

    execution.singleton_class.prepend(diagnostics)
  end

  def drive_async_work(execution_id:, async_execution:)
    if async_execution
      async_execution.finish
    else
      require_test_queue_execution
      assert_subject_owned!(Plywo::Rails::TestQueueExecution.method(:drain), "TestQueueExecution")

      executions = Plywo::Rails::TestQueueExecution.drain(execution_id:)
      {
        "executions" => executions,
        "quiescence" => wait_for_quiescence(execution_id:),
        "transport" => { "name" => "active_job_test_adapter" }
      }
    end
  end

  def require_test_queue_execution
    return if defined?(Plywo::Rails::TestQueueExecution::DEFAULT_MAX_JOBS)

    require File.join(SUBJECT_ROOT, "lib/plywo/rails/test_queue_execution")
  end

  def require_solid_queue_execution
    return if defined?(Plywo::Rails::SolidQueueExecution)

    require File.join(SUBJECT_ROOT, "lib/plywo/rails/solid_queue_execution")
  end

  def assert_subject_owned!(method, component)
    source_path = method.source_location&.first
    subject_prefix = "#{File.expand_path(SUBJECT_ROOT)}#{File::SEPARATOR}"

    return if source_path && File.expand_path(source_path).start_with?(subject_prefix)

    raise "#{component} must be loaded from subject root #{SUBJECT_ROOT}, got #{source_path || "unknown source"}"
  end

  def reset_test_queue
    adapter = ActiveJob::Base.queue_adapter
    adapter.enqueued_jobs.clear if adapter.respond_to?(:enqueued_jobs)
    adapter.performed_jobs.clear if adapter.respond_to?(:performed_jobs)
  end

  def wait_for_quiescence(execution_id:)
    Plywo::Rails::ExecutionQuiescence.wait(
      execution_id:,
      timeout_seconds: Float(ENV.fetch("PLYWO_QUIESCENCE_TIMEOUT_SECONDS", DEFAULT_QUIESCENCE_TIMEOUT_SECONDS)),
      quiet_period_seconds: Float(ENV.fetch("PLYWO_QUIET_PERIOD_SECONDS", DEFAULT_QUIET_PERIOD_SECONDS))
    )
  end

  def durable_observations(execution_id:)
    PlywoEvidenceEvent.where(execution_id:).order(:id).map do |record|
      {
        "signal" => record.signal,
        "path" => record.path,
        "start_line" => record.start_line,
        "end_line" => record.end_line,
        "confidence" => record.confidence,
        "payload" => record.payload,
        "producer_kind" => record.producer_kind,
        "producer_name" => record.producer_name,
        "producer_id" => record.producer_id,
        "occurred_at" => record.occurred_at&.iso8601(6)
      }
    end
  end

  def request
    @request ||= Rack::MockRequest.new(Rails.application)
  end

  def headers(execution_id:, subject:)
    {
      "HTTP_HOST" => "localhost",
      "HTTP_X_PLYWO_EXECUTION_ID" => execution_id,
      "HTTP_X_PLYWO_RUN_ID" => run_id,
      "HTTP_X_PLYWO_SUBJECT" => subject
    }
  end

  def path
    ENV.fetch("PLYWO_SCENARIO_PATH", DEFAULT_PATH)
  end

  def async_transport
    ENV.fetch("PLYWO_ASYNC_TRANSPORT", "test_adapter")
  end

  def run_id
    ENV.fetch("PLYWO_RUN_ID")
  end

  def scenario_id
    ENV.fetch("PLYWO_SCENARIO_ID", DEFAULT_SCENARIO_ID)
  end

  def subject
    ENV.fetch("PLYWO_SUBJECT")
  end

  def label
    ENV.fetch("PLYWO_EXECUTION_LABEL")
  end

  def sha
    ENV.fetch("PLYWO_EXECUTION_SHA")
  end
end

PlywoSubjectCapture.new.call
