module Plywo
  module Executor
    class Resolver
      Error = Class.new(StandardError)

      def self.from_env(root: ::Rails.root, env: ENV, rails_env: ::Rails.env)
        mode = env["PLYWO_EXECUTOR"] || env["PLYWO_GITHUB_EXECUTION_MODE"]
        mode ||= rails_env.development? ? "local" : "disabled"

        case mode
        when "local"
          LocalAdapter.new(root:)
        when "remote"
          remote_adapter(env:)
        when "disabled"
          raise Error, "Plywo executor is disabled"
        else
          raise Error, "Unsupported PLYWO_EXECUTOR=#{mode.inspect}"
        end
      end

      def self.remote_adapter(env:)
        url = env["PLYWO_REMOTE_EXECUTOR_URL"].to_s
        token = env["PLYWO_REMOTE_EXECUTOR_TOKEN"].to_s
        raise Error, "PLYWO_REMOTE_EXECUTOR_URL is required" if url.empty?
        raise Error, "PLYWO_REMOTE_EXECUTOR_TOKEN is required" if token.empty?

        HttpAdapter.new(
          url:,
          token:,
          open_timeout: env.fetch(
            "PLYWO_REMOTE_EXECUTOR_OPEN_TIMEOUT_SECONDS",
            HttpAdapter::DEFAULT_OPEN_TIMEOUT_SECONDS
          ),
          read_timeout: env.fetch(
            "PLYWO_REMOTE_EXECUTOR_READ_TIMEOUT_SECONDS",
            HttpAdapter::DEFAULT_READ_TIMEOUT_SECONDS
          )
        )
      rescue HttpAdapter::Error, ArgumentError => error
        raise Error, error.message
      end
      private_class_method :remote_adapter
    end
  end
end
