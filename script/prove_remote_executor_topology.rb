#!/usr/bin/env ruby

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"

module RemoteExecutorTopologyProof
  class StaticRepositoryCapabilityProvider
    def initialize(token:)
      @capability = Plywo::Executor::RepositoryCapability.new(token:)
    end

    def call(request:)
      @capability
    end
  end

  module_function

  def call
    request = Plywo::Executor::Request.new(
      schema_version: Plywo::Executor::Request.current_schema_version,
      execution_id: ENV.fetch("PLYWO_PROOF_EXECUTION_ID"),
      scenario_id: "production.remote-executor-topology",
      baseline_sha: ENV.fetch("PLYWO_PROOF_BASELINE_SHA"),
      candidate_sha: ENV.fetch("PLYWO_PROOF_CANDIDATE_SHA"),
      attempt_number: 1,
      context: {
        "repository" => ENV.fetch("PLYWO_PROOF_REPOSITORY"),
        "candidate_repository" => ENV.fetch("PLYWO_PROOF_REPOSITORY"),
        "pull_request_number" => Integer(ENV.fetch("PLYWO_PROOF_PULL_REQUEST_NUMBER")),
        "baseline_ref" => ENV.fetch("PLYWO_PROOF_BASELINE_REF"),
        "candidate_ref" => ENV.fetch("PLYWO_PROOF_CANDIDATE_REF")
      }
    )

    adapter = Plywo::Executor::HttpAdapter.new(
      url: ENV.fetch("PLYWO_REMOTE_EXECUTOR_URL"),
      token: ENV.fetch("PLYWO_REMOTE_EXECUTOR_TOKEN"),
      repository_capability_provider: StaticRepositoryCapabilityProvider.new(
        token: ENV.fetch("PLYWO_PROOF_REPOSITORY_TOKEN")
      )
    )

    result = adapter.call(request:)
    unless result.success?
      raise "Remote executor failed: #{result.error_class}: #{result.error_message}"
    end

    payload = result.payload
    unless payload.is_a?(Hash) && payload.dig("executions", "baseline") && payload.dig("executions", "candidate")
      raise "Remote executor returned a successful Result without baseline/candidate behavioral payload"
    end

    puts "Remote executor topology proof"
    puts "request_schema=#{request.schema_version}"
    puts "result_schema=#{result.schema_version}"
    puts "result_status=#{result.status}"
    puts "repository=#{request.context.fetch("repository")}"
    puts "baseline_sha=#{request.baseline_sha}"
    puts "candidate_sha=#{request.candidate_sha}"
    puts "repository_capability_transport=out_of_band_header"
    puts "separate_executor_process=true"
  end
end

RemoteExecutorTopologyProof.call
