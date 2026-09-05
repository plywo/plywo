module Plywo
  module Subject
    class RailsPostgresEnvironment < Environment
      DEFAULT_POSTGRES_URL = "postgres://localhost".freeze

      def initialize(command_runner:, postgres_url: ENV.fetch("PLYWO_LOCAL_POSTGRES_URL", DEFAULT_POSTGRES_URL))
        @command_runner = command_runner
        @postgres_url = postgres_url.sub(%r{/+$}, "")
      end

      def prepare(root:, execution:, role:)
        env = env_for(root:, execution:, role:)
        @command_runner.call(
          env:,
          command: [ root.join("bin", "rails").to_s, "db:prepare" ],
          chdir: root.to_s
        )
        env
      end

      def env_for(root:, execution:, role:)
        {
          "BUNDLE_GEMFILE" => root.join("Gemfile").to_s,
          "RAILS_ENV" => "test",
          "DATABASE_URL" => database_url(execution:, role:),
          "SOLID_QUEUE_DATABASE_URL" => database_url(execution:, role: "#{role}_queue"),
          "PLYWO_SOLID_QUEUE" => "1",
          "PLYWO_ASYNC_TRANSPORT" => "solid_queue",
          "PLYWO_SOLID_QUEUE_DIAGNOSTICS" => "1",
          "PLYWO_SOLID_QUEUE_START_TIMEOUT_SECONDS" => "30",
          "PLYWO_QUIESCENCE_TIMEOUT_SECONDS" => "30",
          "SOLID_QUEUE_SKIP_RECURRING" => "true",
          "SOLID_QUEUE_SUPERVISOR_MODE" => "async"
        }
      end

      private

      def database_url(execution:, role:)
        suffix = execution.execution_id.delete_prefix("github-")[0, 12]
        "#{@postgres_url}/plywo_app_#{suffix}_#{role}"
      end
    end
  end
end
