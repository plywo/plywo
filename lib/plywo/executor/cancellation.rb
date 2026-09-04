module Plywo
  module Executor
    class Cancellation
      def initialize(notification_job: PlywoExecutorCancellationJob)
        @notification_job = notification_job
      end

      def call(execution:, reason: "cancelled")
        attempt_number = execution.attempt_count
        return false unless execution.cancel!(attempt_number:, reason:)

        if attempt_number.positive?
          @notification_job.perform_later(execution.execution_id, attempt_number, reason.to_s)
        end

        true
      end
    end
  end
end
