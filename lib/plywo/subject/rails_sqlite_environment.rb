require "fileutils"
require "rbconfig"

module Plywo
  module Subject
    class RailsSqliteEnvironment < Environment
      def initialize(command_runner:, state_root: nil, bundle_path: nil, bundle_app_config: nil)
        @command_runner = command_runner
        @state_root = state_root && Pathname(state_root).expand_path
        @bundle_path = bundle_path && Pathname(bundle_path).expand_path.to_s
        @bundle_app_config = bundle_app_config && Pathname(bundle_app_config).expand_path.to_s
      end

      def prepare(root:, execution:, role:)
        path = database_path(root:, execution:, role:)
        FileUtils.mkdir_p(path.dirname)
        remove_database_files(path)

        env = env_for(root:, execution:, role:)
        @command_runner.call(
          env:,
          command: [ RbConfig.ruby, root.join("bin", "rails").to_s, "db:prepare" ],
          chdir: root.to_s
        )
        env
      end

      def env_for(root:, execution:, role:)
        env = {
          "BUNDLE_GEMFILE" => root.join("Gemfile").to_s,
          "DATABASE_URL" => nil,
          "SOLID_QUEUE_DATABASE_URL" => nil,
          "RAILS_ENV" => "test",
          "PLYWO_SQLITE_DATABASE" => database_path(root:, execution:, role:).to_s,
          "PLYWO_ASYNC_TRANSPORT" => "test_adapter",
          "PLYWO_QUIESCENCE_TIMEOUT_SECONDS" => "30",
          "PLYWO_QUIET_PERIOD_SECONDS" => "0.01"
        }
        env["BUNDLE_PATH"] = @bundle_path if @bundle_path
        env["BUNDLE_APP_CONFIG"] = @bundle_app_config if @bundle_app_config
        env
      end

      def cleanup(root:, execution:, role:)
        remove_database_files(database_path(root:, execution:, role:))
      end

      private

      def database_path(root:, execution:, role:)
        directory = @state_root || root.join("tmp", "plywo", "sqlite")
        suffix = execution.execution_id.delete_prefix("github-")[0, 12]
        directory.join("plywo_subject_#{suffix}_#{role}.sqlite3")
      end

      def remove_database_files(path)
        FileUtils.rm_f(path)
        FileUtils.rm_f("#{path}-wal")
        FileUtils.rm_f("#{path}-shm")
      end
    end
  end
end
