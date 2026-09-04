class PlywoExecutorJob < ApplicationJob
  queue_as :default

  def perform(request_payload)
    execution_id = request_payload.fetch("execution_id")
    request = Plywo::Executor::Request.from_h(request_payload)
    result = execute(request:)

    finalizer_job_class.perform_later(execution_id, result.to_h)
  end

  private

  def execute(request:)
    Plywo::Executor::Result.success(executor.call(request:))
  rescue StandardError => error
    Plywo::Executor::Result.failure(error)
  end

  def executor
    Plywo::Executor::Resolver.from_env(root: Rails.root)
  end

  def finalizer_job_class
    GithubPullRequestExecutionFinalizeJob
  end
end
