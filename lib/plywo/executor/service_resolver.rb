module Plywo
  module Executor
    class ServiceResolver
      Error = Class.new(StandardError)

      def self.from_env(root: ::Rails.root, env: ENV)
        mode = env.fetch("PLYWO_EXECUTOR_SERVICE_ADAPTER", "local")

        case mode
        when "local"
          LocalAdapter.new(root:)
        when "git_clone"
          GitCloneAdapter.new(root:)
        when "disabled"
          raise Error, "Plywo executor service adapter is disabled"
        else
          raise Error, "Unsupported PLYWO_EXECUTOR_SERVICE_ADAPTER=#{mode.inspect}"
        end
      end
    end
  end
end
