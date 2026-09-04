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
      "attributions" => collector.respond_to?(:attributions) ? collector.attributions : {}
    }

    File.write(ENV.fetch("PLYWO_OUTPUT"), JSON.pretty_generate(payload))
    puts JSON.pretty_generate(payload)
  end

  private

  def warm_runtime
    ApplicationRecord.connection.select_value("SELECT 1")
    request.post(path, headers(execution_id: "warmup", subject: "warmup"))
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
