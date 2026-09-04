require "fileutils"
require "json"
require "open3"
require "rbconfig"

module Plywo
  module Github
    class LocalPullRequestRunner
      Error = Class.new(StandardError)
      DEFAULT_POSTGRES_URL = "postgres://localhost".freeze

      class CommandRunner
        def call(env:, command:, chdir:)
          stdout, stderr, status = Open3.capture3(env, *command, chdir:)
          return stdout if status.success?

          raise Error, "Command failed (#{command.join(" ")}): #{stderr.presence || stdout}"
        end
      end

      def initialize(root: Rails.root, tool_root: root, command_runner: CommandRunner.new, fetch_repository: true)
        @root = Pathname(root).expand_path
        @tool_root = Pathname(tool_root).expand_path
        @command_runner = command_runner
        @fetch_repository = fetch_repository
      end

      def call(execution:)
        context = execution.context
        assert_local_subject!(context:)
        fetch_repository! if @fetch_repository
        assert_commit!(execution.baseline_sha)
        assert_commit!(execution.candidate_sha)

        paths = execution_paths(execution:)
        prepare_worktree!(path: paths.fetch(:baseline_root), sha: execution.baseline_sha)
        prepare_worktree!(path: paths.fetch(:candidate_root), sha: execution.candidate_sha)

        prepare_database!(
          root: paths.fetch(:baseline_root),
          primary_url: database_url(execution:, role: "base"),
          queue_url: database_url(execution:, role: "base_queue")
        )
        prepare_database!(
          root: paths.fetch(:candidate_root),
          primary_url: database_url(execution:, role: "candidate"),
          queue_url: database_url(execution:, role: "candidate_queue")
        )

        capture_subject!(
          execution:,
          root: paths.fetch(:baseline_root),
          label: context.fetch("baseline_ref"),
          sha: execution.baseline_sha,
          primary_url: database_url(execution:, role: "base"),
          queue_url: database_url(execution:, role: "base_queue"),
          output: paths.fetch(:baseline_output)
        )
        capture_subject!(
          execution:,
          root: paths.fetch(:candidate_root),
          label: context.fetch("candidate_ref"),
          sha: execution.candidate_sha,
          primary_url: database_url(execution:, role: "candidate"),
          queue_url: database_url(execution:, role: "candidate_queue"),
          output: paths.fetch(:candidate_output)
        )

        compare(
          baseline_output: paths.fetch(:baseline_output),
          candidate_output: paths.fetch(:candidate_output),
          changed_paths: changed_paths(execution:)
        )
      ensure
        cleanup_worktree(paths&.fetch(:baseline_root, nil))
        cleanup_worktree(paths&.fetch(:candidate_root, nil))
      end

      private

      def assert_local_subject!(context:)
        candidate_repository = context.fetch("candidate_repository")
        repository = context.fetch("repository")
        return if candidate_repository == repository

        raise Error, "Local GitHub runner only supports same-repository pull requests"
      end

      def fetch_repository!
        run!(command: %w[git fetch --prune origin], chdir: @root)
      end

      def assert_commit!(sha)
        run!(command: [ "git", "cat-file", "-e", "#{sha}^{commit}" ], chdir: @root)
      end

      def execution_paths(execution:)
        directory = @root.join("tmp", "plywo", "github", execution.execution_id.delete_prefix("github-")[0, 16])
        FileUtils.mkdir_p(directory)

        {
          baseline_root: directory.join("base"),
          candidate_root: directory.join("candidate"),
          baseline_output: directory.join("base.json"),
          candidate_output: directory.join("candidate.json")
        }
      end

      def prepare_worktree!(path:, sha:)
        cleanup_worktree(path)
        FileUtils.rm_rf(path)
        run!(command: [ "git", "worktree", "add", "--detach", path.to_s, sha ], chdir: @root)
      end

      def prepare_database!(root:, primary_url:, queue_url:)
        run!(
          env: subject_environment(root:, primary_url:, queue_url:),
          command: [ root.join("bin", "rails").to_s, "db:prepare" ],
          chdir: root
        )
      end

      def capture_subject!(execution:, root:, label:, sha:, primary_url:, queue_url:, output:)
        env = subject_environment(root:, primary_url:, queue_url:).merge(
          "PLYWO_RUN_ID" => execution.execution_id,
          "PLYWO_SCENARIO_ID" => execution.scenario_id,
          "PLYWO_SUBJECT" => "github-pull-request",
          "PLYWO_EXECUTION_LABEL" => label,
          "PLYWO_EXECUTION_SHA" => sha,
          "PLYWO_OUTPUT" => output.to_s
        )

        run!(
          env:,
          command: [ RbConfig.ruby, @tool_root.join("script", "plywo_capture_subject.rb").to_s ],
          chdir: root
        )
      end

      def subject_environment(root:, primary_url:, queue_url:)
        {
          "BUNDLE_GEMFILE" => root.join("Gemfile").to_s,
          "RAILS_ENV" => "test",
          "DATABASE_URL" => primary_url,
          "SOLID_QUEUE_DATABASE_URL" => queue_url,
          "PLYWO_SOLID_QUEUE" => "1",
          "PLYWO_ASYNC_TRANSPORT" => "solid_queue",
          "PLYWO_SOLID_QUEUE_DIAGNOSTICS" => "1",
          "PLYWO_SOLID_QUEUE_START_TIMEOUT_SECONDS" => "30",
          "PLYWO_QUIESCENCE_TIMEOUT_SECONDS" => "30",
          "SOLID_QUEUE_SKIP_RECURRING" => "true",
          "SOLID_QUEUE_SUPERVISOR_MODE" => "async"
        }
      end

      def changed_paths(execution:)
        output = run!(
          command: [ "git", "diff", "--name-only", "#{execution.baseline_sha}...#{execution.candidate_sha}" ],
          chdir: @root
        )
        output.lines(chomp: true).reject(&:empty?)
      end

      def compare(baseline_output:, candidate_output:, changed_paths:)
        baseline = Plywo::ExecutionReducer.call(execution: JSON.parse(File.read(baseline_output)))
        candidate = Plywo::ExecutionReducer.call(execution: JSON.parse(File.read(candidate_output)))
        Plywo::ExecutionPair.call(baseline:, candidate:, changed_paths:)
      end

      def database_url(execution:, role:)
        prefix = ENV.fetch("PLYWO_LOCAL_POSTGRES_URL", DEFAULT_POSTGRES_URL).sub(%r{/+$}, "")
        suffix = execution.execution_id.delete_prefix("github-")[0, 12]
        "#{prefix}/plywo_app_#{suffix}_#{role}"
      end

      def cleanup_worktree(path)
        return unless path

        run!(
          command: [ "git", "worktree", "remove", "--force", path.to_s ],
          chdir: @root,
          allow_failure: true
        )
        FileUtils.rm_rf(path)
        run!(command: %w[git worktree prune], chdir: @root, allow_failure: true)
      end

      def run!(command:, chdir:, env: {}, allow_failure: false)
        @command_runner.call(env:, command:, chdir: chdir.to_s)
      rescue Error
        raise unless allow_failure

        ""
      end
    end
  end
end
