require "fileutils"
require "shellwords"

module Plywo
  module Github
    class DevelopmentCredentialStore
      attr_reader :private_key_path, :env_path

      def initialize(root: ::Rails.root)
        @root = root
        @directory = @root.join("tmp/github-app")
        @private_key_path = @directory.join("plywo-development.pem")
        @env_path = @directory.join("development.env")
      end

      def write!(credentials)
        FileUtils.mkdir_p(@directory)

        @private_key_path.write(credentials.fetch("pem"))
        File.chmod(0o600, @private_key_path)

        values = {
          "PLYWO_GITHUB_APP_ID" => credentials.fetch("id").to_s,
          "PLYWO_GITHUB_CLIENT_ID" => credentials.fetch("client_id"),
          "PLYWO_GITHUB_WEBHOOK_SECRET" => credentials.fetch("webhook_secret"),
          "PLYWO_GITHUB_PRIVATE_KEY_PATH" => @private_key_path.relative_path_from(@root).to_s
        }

        @env_path.write(
          values.map { |key, value| "export #{key}=#{Shellwords.escape(value)}" }.join("\n") + "\n"
        )
        File.chmod(0o600, @env_path)

        values.each { |key, value| ENV[key] = value }
        self
      end
    end
  end
end
