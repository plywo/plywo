class PlywoExecutorCancellationJob < ApplicationJob
  queue_as :default

  def perform(execution_id, attempt_number, reason = "cancelled")
    execution = PlywoExecution.find_by(execution_id:)
    return unless execution
    return unless execution.status == "cancelled"
    return unless execution.attempt_count == Integer(attempt_number)

    executor.cancel(
      execution_id:,
      attempt_number:,
      reason:
    )
  rescue StandardError => error
    Rails.logger.warn(
      "Plywo executor cancellation delivery failed execution_id=#{execution_id.inspect} " \
      "attempt=#{attempt_number.inspect} error=#{error.class}"
    )
  end

  private

  def executor
    Plywo::Executor::Resolver.from_env(root: Rails.root)
  end
end
