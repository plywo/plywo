require "digest"

module Plywo
  module Github
    class ExecutionDispatcher
      DEFAULT_SCENARIO_ID = "dogfood.git.behavior".freeze

      def initialize(scenario_id: ENV.fetch("PLYWO_SCENARIO_ID", DEFAULT_SCENARIO_ID))
        @scenario_id = scenario_id
      end

      def call(delivery:, pull_request:)
        context = build_context(delivery:, pull_request:)
        execution_id = execution_id_for(context:)
        existing = PlywoExecution.find_by(execution_id:)

        if existing
          return [ existing, true ] if existing.status == "queued"

          if existing.status == "failed"
            existing.update!(
              status: "queued",
              decision: nil,
              result: {},
              failure: nil,
              started_at: nil,
              finished_at: nil
            )
            return [ existing, true ]
          end

          return [ existing, false ]
        end

        execution = PlywoExecution.create!(
          execution_id:,
          source: "github_pull_request",
          scenario_id: @scenario_id,
          baseline_sha: context.fetch("baseline_sha"),
          candidate_sha: context.fetch("candidate_sha"),
          context:
        )

        [ execution, true ]
      rescue ActiveRecord::RecordNotUnique
        execution = PlywoExecution.find_by!(execution_id:)
        [ execution, execution.status == "queued" ]
      end

      private

      def build_context(delivery:, pull_request:)
        {
          "repository" => delivery.repository,
          "pull_request_number" => delivery.pull_request_number,
          "installation_id" => delivery.installation_id,
          "delivery_id" => delivery.delivery_id,
          "baseline_ref" => pull_request.dig("base", "ref"),
          "baseline_sha" => pull_request.dig("base", "sha"),
          "candidate_ref" => pull_request.dig("head", "ref"),
          "candidate_sha" => pull_request.dig("head", "sha"),
          "candidate_repository" => pull_request.dig("head", "repo", "full_name")
        }
      end

      def execution_id_for(context:)
        identity = [
          context.fetch("repository"),
          context.fetch("pull_request_number"),
          context.fetch("baseline_sha"),
          context.fetch("candidate_sha"),
          @scenario_id
        ].join("\0")

        "github-#{Digest::SHA256.hexdigest(identity)}"
      end
    end
  end
end
