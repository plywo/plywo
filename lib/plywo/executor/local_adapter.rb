module Plywo
  module Executor
    class LocalAdapter
      def initialize(root: ::Rails.root, runner: nil)
        @runner = runner || Plywo::Github::LocalPullRequestRunner.new(root:)
      end

      def call(request:)
        Result.success(@runner.call(execution: request))
      rescue StandardError => error
        Result.failure(error)
      end
    end
  end
end
