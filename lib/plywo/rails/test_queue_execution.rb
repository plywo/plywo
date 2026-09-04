module Plywo
  module Rails
    class TestQueueExecution
      def self.drain(execution_id:, adapter: ActiveJob::Base.queue_adapter)
        new(execution_id:, adapter:).drain
      end

      def initialize(execution_id:, adapter:)
        @execution_id = execution_id.to_s
        @adapter = adapter
      end

      def drain
        jobs = matching_jobs
        jobs.each { |job_data| @adapter.enqueued_jobs.delete(job_data) }

        Current.reset

        jobs.map do |job_data|
          serialized = serialized_job(job_data)
          context = serialized.fetch(ActiveJobExecutionContext::CONTEXT_KEY, {})

          ActiveJob::Base.execute(serialized)

          {
            "job_class" => serialized.fetch("job_class"),
            "job_id" => serialized.fetch("job_id"),
            "queue_name" => serialized.fetch("queue_name"),
            "execution_id" => context["plywo_execution_id"],
            "run_id" => context["plywo_run_id"],
            "subject" => context["plywo_subject"],
            "source" => "application_enqueue"
          }
        ensure
          Current.reset
        end
      end

      private

      def matching_jobs
        @adapter.enqueued_jobs.select do |job_data|
          context = serialized_job(job_data)[ActiveJobExecutionContext::CONTEXT_KEY]
          context&.fetch("plywo_execution_id", nil).to_s == @execution_id
        end
      end

      def serialized_job(job_data)
        job_data.each_with_object({}) do |(key, value), result|
          result[key] = value if key.is_a?(String)
        end
      end
    end
  end
end
