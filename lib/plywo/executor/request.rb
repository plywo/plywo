module Plywo
  module Executor
    Request = Data.define(
      :schema_version,
      :execution_id,
      :scenario_id,
      :baseline_sha,
      :candidate_sha,
      :attempt_number,
      :context
    ) do
      SCHEMA_VERSION = "1".freeze
      CONTEXT_KEYS = %w[
        repository
        pull_request_number
        baseline_ref
        candidate_ref
        candidate_repository
      ].freeze

      def self.from_execution(execution)
        new(
          schema_version: SCHEMA_VERSION,
          execution_id: execution.execution_id,
          scenario_id: execution.scenario_id,
          baseline_sha: execution.baseline_sha,
          candidate_sha: execution.candidate_sha,
          attempt_number: execution.attempt_count,
          context: execution.context.slice(*CONTEXT_KEYS)
        )
      end

      def self.from_h(payload)
        payload = payload.transform_keys(&:to_s)
        schema_version = payload.fetch("schema_version")
        raise ArgumentError, "Unsupported executor request schema #{schema_version.inspect}" unless schema_version == SCHEMA_VERSION

        new(
          schema_version:,
          execution_id: payload.fetch("execution_id"),
          scenario_id: payload.fetch("scenario_id"),
          baseline_sha: payload.fetch("baseline_sha"),
          candidate_sha: payload.fetch("candidate_sha"),
          attempt_number: Integer(payload.fetch("attempt_number")),
          context: payload.fetch("context").transform_keys(&:to_s).slice(*CONTEXT_KEYS)
        )
      end

      def to_h
        {
          "schema_version" => schema_version,
          "execution_id" => execution_id,
          "scenario_id" => scenario_id,
          "baseline_sha" => baseline_sha,
          "candidate_sha" => candidate_sha,
          "attempt_number" => attempt_number,
          "context" => context
        }
      end
    end
  end
end
