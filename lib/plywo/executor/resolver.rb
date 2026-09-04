module Plywo
  module Executor
    class Resolver
      Error = Class.new(StandardError)

      def self.from_env(root: Rails.root, env: ENV, rails_env: Rails.env)
        mode = env["PLYWO_EXECUTOR"] || env["PLYWO_GITHUB_EXECUTION_MODE"]
        mode ||= rails_env.development? ? "local" : "disabled"

        case mode
        when "local"
          LocalAdapter.new(root:)
        when "disabled"
          raise Error, "Plywo executor is disabled"
        else
          raise Error, "Unsupported PLYWO_EXECUTOR=#{mode.inspect}"
        end
      end
    end
  end
end
