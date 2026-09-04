require "base64"
require "fileutils"

module Plywo
  module Executor
    class GitCloneAdapter
      Error = Class.new(StandardError)
      REPOSITORY_PATTERN = %r{\A[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+\z}.freeze

      def initialize(
        root: ::Rails.root,
        command_runner: Plywo::Github::LocalPullRequestRunner::CommandRunner.new,
        runner_factory: nil
      )
        @root = Pathname(root).expand_path
        @command_runner = command_runner
        @runner_factory = runner_factory || lambda do |repository_root:|
          Plywo::Github::LocalPullRequestRunner.new(
            root: repository_root,
            tool_root: @root,
            fetch_repository: false
          )
        end
      end

      def call(request:, repository_capability: nil)
        raise Error, "Repository capability is required for git clone execution" unless repository_capability

        context = request.context
        repository = context.fetch("repository")
        candidate_repository = context.fetch("candidate_repository")
        unless repository == candidate_repository
          raise Error, "Git clone executor currently supports same-repository pull requests only"
        end
        raise Error, "Executor repository must use owner/name form" unless REPOSITORY_PATTERN.match?(repository)

        repository_root = repository_root(request:)
        prepare_repository!(
          repository_root:,
          repository:,
          pull_request_number: Integer(context.fetch("pull_request_number")),
          baseline_ref: context.fetch("baseline_ref"),
          repository_capability:
        )
        assert_commit!(repository_root:, sha: request.baseline_sha)
        assert_commit!(repository_root:, sha: request.candidate_sha)

        runner = @runner_factory.call(repository_root:)
        Result.success(runner.call(execution: request))
      rescue StandardError => error
        Result.failure(error)
      ensure
        FileUtils.rm_rf(repository_root) if repository_root
      end

      private

      def prepare_repository!(repository_root:, repository:, pull_request_number:, baseline_ref:, repository_capability:)
        FileUtils.rm_rf(repository_root)
        FileUtils.mkdir_p(repository_root.dirname)

        run!(command: [ "git", "init", repository_root.to_s ], chdir: @root)
        run!(
          command: [ "git", "remote", "add", "origin", "https://github.com/#{repository}.git" ],
          chdir: repository_root
        )
        run!(
          env: git_auth_environment(repository_capability:),
          command: [
            "git", "fetch", "--no-tags", "--filter=blob:none", "origin",
            "+refs/heads/#{baseline_ref}:refs/remotes/origin/plywo-base",
            "+refs/pull/#{pull_request_number}/head:refs/remotes/origin/plywo-candidate"
          ],
          chdir: repository_root
        )
      end

      def assert_commit!(repository_root:, sha:)
        run!(command: [ "git", "cat-file", "-e", "#{sha}^{commit}" ], chdir: repository_root)
      end

      def git_auth_environment(repository_capability:)
        basic = Base64.strict_encode64("x-access-token:#{repository_capability.token}")
        {
          "GIT_TERMINAL_PROMPT" => "0",
          "GIT_CONFIG_COUNT" => "1",
          "GIT_CONFIG_KEY_0" => "http.https://github.com/.extraheader",
          "GIT_CONFIG_VALUE_0" => "AUTHORIZATION: basic #{basic}"
        }
      end

      def repository_root(request:)
        suffix = request.execution_id.delete_prefix("github-")[0, 16]
        @root.join("tmp", "plywo", "repositories", suffix)
      end

      def run!(command:, chdir:, env: {})
        @command_runner.call(env:, command:, chdir: chdir.to_s)
      end
    end
  end
end
