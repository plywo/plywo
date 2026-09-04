class GithubPullRequestExecutionFinalizeJob < ApplicationJob
  queue_as :default

  def perform(execution_id, result_payload)
    execution = PlywoExecution.find_by!(execution_id:)
    unless execution.renew_lease!
      Rails.logger.info(
        "Plywo GitHub executor result ignored execution_id=#{execution.execution_id.inspect} " \
        "reason=lease_expired_or_terminal"
      )
      return
    end

    result = Plywo::Executor::Result.from_h(result_payload)
    token = installation_token(execution:)
    pull_request = current_pull_request(execution:, token: token.value)
    if (reason = stale_reason(execution:, pull_request:))
      ignore_stale!(execution:, reason: "#{reason}_before_finalize")
      return
    end

    if result.failure?
      finalize_infra_failure(execution:, result:, token:)
      return
    end

    finalize_success(execution:, payload: result.payload, token:)
  rescue StandardError => error
    if execution&.status == "running"
      execution.fail!(error)
      publish_infra_failure(execution:, error:)
    end
    raise
  end

  private

  def finalize_success(execution:, payload:, token:)
    publication = execution_publisher(token: token.value).call(execution:, payload:)
    if publication.fetch(:comment) == :stale
      execution.ignore!("stale_during_publish")
      return
    end

    execution.complete!(payload)
    Rails.logger.info(
      "Plywo GitHub execution finalized execution_id=#{execution.execution_id.inspect} " \
      "decision=#{execution.decision.inspect} outcome=#{execution.outcome.inspect} " \
      "attempt=#{execution.attempt_count.inspect} check=#{publication.fetch(:check).inspect} " \
      "comment=#{publication.fetch(:comment).inspect}"
    )
  end

  def finalize_infra_failure(execution:, result:, token:)
    execution.fail_details!(error_class: result.error_class, error_message: result.error_message)
    publication = execution_publisher(token: token.value).infra_failure(
      execution:,
      error_class: result.error_class
    )

    Rails.logger.info(
      "Plywo GitHub execution infra failure finalized execution_id=#{execution.execution_id.inspect} " \
      "attempt=#{execution.attempt_count.inspect} error_class=#{result.error_class.inspect} " \
      "check=#{publication.fetch(:check).inspect} comment=#{publication.fetch(:comment).inspect}"
    )
  end

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

    execution_publisher(token: token.value).infra_failure(execution:, error:)
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

  def execution_publisher(token:)
    Plywo::Github::PullRequestExecutionPublisher.new(token:)
  end
end
