class GithubPullRequestExecutionJob < ApplicationJob
  queue_as :control

  def perform(execution_record_id)
    execution = PlywoExecution.find(execution_record_id)
    return unless execution.claim!

    token = installation_token(execution:)
    pull_request = current_pull_request(execution:, token: token.value)
    if (reason = stale_reason(execution:, pull_request:))
      ignore_stale!(execution:, reason:)
      return
    end

    request = Plywo::Executor::Request.from_execution(execution)
    heartbeat_job_class.schedule(execution.execution_id, execution.attempt_count)
    executor_job_class.perform_later(request.to_h)

    Rails.logger.info(
      "Plywo GitHub execution dispatched execution_id=#{execution.execution_id.inspect} " \
      "repository=#{execution.context.fetch("repository").inspect} " \
      "pr=#{execution.context.fetch("pull_request_number").inspect} " \
      "attempt=#{execution.attempt_count.inspect}"
    )
  rescue StandardError => error
    if execution&.fail!(error)
      publish_infra_failure(execution:, error:)
    end
    raise
  end

  private

  def installation_token(execution:)
    app_authentication.installation_token(
      installation_id: Integer(execution.context.fetch("installation_id"))
    )
  end

  def current_pull_request(execution:, token:)
    pull_request_client(token:).fetch(
      repository: execution.context.fetch("repository"),
      number: Integer(execution.context.fetch("pull_request_number"))
    )
  end

  def stale_reason(execution:, pull_request:)
    return "stale_head" if pull_request.dig("head", "sha") != execution.candidate_sha
    return "stale_baseline" if pull_request.dig("base", "sha") != execution.baseline_sha

    nil
  end

  def ignore_stale!(execution:, reason:)
    execution.ignore!(reason)
    Rails.logger.info(
      "Plywo GitHub execution ignored execution_id=#{execution.execution_id.inspect} reason=#{reason.inspect}"
    )
  end

  def publish_infra_failure(execution:, error:)
    token = installation_token(execution:)
    pull_request = current_pull_request(execution:, token: token.value)
    return if stale_reason(execution:, pull_request:)

    publication = execution_publisher(token: token.value).infra_failure(execution:, error:)
    Rails.logger.info(
      "Plywo GitHub execution infra failure execution_id=#{execution.execution_id.inspect} " \
      "attempt=#{execution.attempt_count.inspect} check=#{publication.fetch(:check).inspect} " \
      "comment=#{publication.fetch(:comment).inspect}"
    )
  rescue StandardError => publication_error
    Rails.logger.error(
      "Plywo GitHub infra failure publication failed execution_id=#{execution.execution_id.inspect} " \
      "error=#{publication_error.class}"
    )
  end

  def app_authentication
    Plywo::Github::AppAuthentication.from_env(root: ::Rails.root)
  end

  def pull_request_client(token:)
    Plywo::Github::PullRequestClient.new(token:)
  end

  def executor_job_class
    PlywoExecutorJob
  end

  def heartbeat_job_class
    GithubPullRequestExecutionHeartbeatJob
  end

  def execution_publisher(token:)
    Plywo::Github::PullRequestExecutionPublisher.new(token:)
  end
end
