module Plywo
  module Executor
    class LocalAdapter
      def initialize(root: Rails.root, runner: nil)
        @runner = runner || Plywo::Github::LocalPullRequestRunner.new(root:)
      end

      def call(request:)
        @runner.call(execution: request)
      end
    end
  end
end
