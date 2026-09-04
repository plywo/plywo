module Plywo
  module Github
    class PullRequestExecutionPublisher
      DEFAULT_CHECK_NAME = "Plywo Development / Behavioral Diff".freeze
      DEFAULT_BOT_LOGIN = "plywo-development[bot]".freeze

      def initialize(
        token:,
        api_url: ENV.fetch("GITHUB_API_URL", "https://api.github.com"),
        check_name: ENV.fetch("PLYWO_GITHUB_APP_CHECK_NAME", DEFAULT_CHECK_NAME),
        bot_login: ENV.fetch("PLYWO_GITHUB_APP_BOT_LOGIN", DEFAULT_BOT_LOGIN)
      )
        @token = token
        @api_url = api_url
        @check_name = check_name
        @bot_login = bot_login
      end

      def call(execution:, payload:)
        context = execution.context
        repository = context.fetch("repository")
        pr_number = Integer(context.fetch("pull_request_number"))
        run_url = "https://github.com/#{repository}/pull/#{pr_number}"
        rendered = CheckRenderer.call(payload:, run_url:)

        check_action = CheckPublisher.new(token: @token, api_url: @api_url).upsert(
          repository:,
          head_sha: execution.candidate_sha,
          name: @check_name,
          external_id: execution.execution_id,
          details_url: run_url,
          conclusion: rendered.fetch("conclusion"),
          title: rendered.fetch("title"),
          summary: rendered.fetch("summary"),
          annotations: rendered.fetch("annotations")
        )

        markdown = CommentRenderer.markdown(
          payload:,
          context: {
            repository:,
            pr_number:,
            baseline_label: context.fetch("baseline_ref"),
            baseline_sha: execution.baseline_sha,
            candidate_label: context.fetch("candidate_ref"),
            candidate_sha: execution.candidate_sha,
            bootstrap_baseline: nil,
            execution_mode: "Plywo Development App - exact Git worktrees + isolated PostgreSQL + Solid Queue",
            run_url:
          }
        )

        comment_action = CommentPublisher.new(token: @token, api_url: @api_url).upsert(
          repository:,
          pr_number:,
          body: markdown,
          author: @bot_login,
          expected_head_sha: execution.candidate_sha
        )

        { check: check_action, comment: comment_action }
      end
    end
  end
end
