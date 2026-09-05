require "fileutils"
require "json"
require "open3"
require "rbconfig"

module Plywo
  module Github
    class LocalPullRequestRunner
      Error = Class.new(StandardError)

      class CommandRunner
        def call(env:, command:, chdir:)
          stdout, stderr, status = Open3.capture3(env, *command, chdir:)
          return stdout if status.success?

          raise Error, "Command failed (#{command.join(" ")}): #{stderr.presence || stdout}"
        end
      end

      def initialize(
        root: Rails.root,
        tool_root: root,
        command_runner: CommandRunner.new,
        fetch_repository: true,
        subject_environment: nil
      )
        @root = Pathname(root).expand_path
        @tool_root = Pathname(tool_root).expand_path
        @command_runner = command_runner
        @fetch_repository = fetch_repository
        @subject_environment = subject_environment || Plywo::Subject::RailsPostgresEnvironment.new(command_runner:)
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

        baseline_env = @subject_environment.prepare(
          root: paths.fetch(:baseline_root),
          execution:,
          role: "base"
        )
        candidate_env = @subject_environment.prepare(
          root: paths.fetch(:candidate_root),
          execution:,
          role: "candidate"
        )

        capture_subject!(
          execution:,
          root: paths.fetch(:baseline_root),
          label: context.fetch("baseline_ref"),
          sha: execution.baseline_sha,
          environment: baseline_env,
          output: paths.fetch(:baseline_output)
        )
        capture_subject!(
          execution:,
          root: paths.fetch(:candidate_root),
          label: context.fetch("candidate_ref"),
          sha: execution.candidate_sha,
          environment: candidate_env,
          output: paths.fetch(:candidate_output)
        )

        compare(
          baseline_output: paths.fetch(:baseline_output),
          candidate_output: paths.fetch(:candidate_output),
          changed_paths: changed_paths(execution:)
        )
      ensure
        if paths
          @subject_environment.cleanup(root: paths.fetch(:candidate_root), execution:, role: "candidate")
          @subject_environment.cleanup(root: paths.fetch(:baseline_root), execution:, role: "base")
        end
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

      def capture_subject!(execution:, root:, label:, sha:, environment:, output:)
        env = environment.merge(
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
