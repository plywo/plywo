module Plywo
  module Executor
    class LocalAdapter
      def initialize(root: ::Rails.root, runner: nil)
        @runner = runner || Plywo::Github::LocalPullRequestRunner.new(root:)
      end

      def call(request:, repository_capability: nil)
        Result.success(@runner.call(execution: request))
      rescue StandardError => error
        Result.failure(error)
      end

      def cancel(execution_id:, attempt_number:, reason: "control_plane_cancelled")
        execution_id
        attempt_number
        reason
        true
      end
    end
  end
end
