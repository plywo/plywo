#!/usr/bin/env ruby

require "json"
require "rack/mock"
require "securerandom"

require File.join(Dir.pwd, "config/environment")

class PlywoSubjectCapture
  DEFAULT_PATH = "/__plywo/demo/behavior".freeze
  DEFAULT_SCENARIO_ID = "dogfood.git.behavior".freeze

  def call
    warm_runtime

    execution_id = SecureRandom.uuid
    response = nil
    collector = Plywo::Rails::EvidenceCollector.new(execution_id:)
    measurements = collector.capture do
      response = request.post(path, headers(execution_id:, subject:))
    end
    passed = response.status.between?(200, 299)
    measurements["errors"] += 1 unless passed

    Current.reset
    perform_durable_worker(execution_id:)

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
      "measurements" => measurements,
      "attributions" => collector.respond_to?(:attributions) ? collector.attributions : {},
      "durable_observations" => durable_observations(execution_id:),
      "lifecycle" => {
        "foreground_collector_closed_before_worker" => true,
        "current_cleared_before_worker" => true
      }
    }

    File.write(ENV.fetch("PLYWO_OUTPUT"), JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload)
  ensure
    Current.reset
  end

  private

  def warm_runtime
    ApplicationRecord.connection.select_value("SELECT 1")
    request.post(path, headers(execution_id: "warmup", subject: "warmup"))
  end

  def perform_durable_worker(execution_id:)
    serialized = Current.set(
      plywo_execution_id: execution_id,
      plywo_run_id: run_id,
      plywo_subject: subject
    ) do
      DemoAsyncEvidenceJob.new.serialize
    end

    Current.reset
    ActiveJob::Base.deserialize(serialized).perform_now
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
