module Plywo
  module Rails
    module ActiveJobExecutionContext
      CONTEXT_KEY = "plywo_execution_context"
      CONTEXT_ATTRIBUTES = %w[plywo_execution_id plywo_run_id plywo_subject].freeze

      def self.included(base)
        base.before_enqueue do |job|
          job.send(:register_plywo_work_item)
        end

        base.around_perform do |job, block|
          job.send(:with_plywo_execution_context) do
            job.send(:capture_plywo_worker_evidence, &block)
          end
        end
      end

      def serialize
        super.merge(CONTEXT_KEY => plywo_execution_context)
      end

      def deserialize(job_data)
        @plywo_execution_context = normalize_plywo_execution_context(job_data[CONTEXT_KEY])
        super
      end

      private

      def plywo_execution_context
        @plywo_execution_context ||= CONTEXT_ATTRIBUTES.each_with_object({}) do |attribute, context|
          value = Current.public_send(attribute)
          context[attribute] = value unless value.nil?
        end
      end

      def normalize_plywo_execution_context(context)
        return {} unless context.respond_to?(:to_h)

        context.to_h.slice(*CONTEXT_ATTRIBUTES).transform_keys(&:to_s)
      end

      def register_plywo_work_item
        context = plywo_execution_context
        return if context["plywo_execution_id"].blank?

        ExecutionWorkLifecycle.enqueued(self, context:)
      end

      def with_plywo_execution_context
        context = @plywo_execution_context
        return yield if context.nil? || context.empty?

        Current.set(**context.transform_keys(&:to_sym)) { yield }
      end

      def capture_plywo_worker_evidence
        execution_id = Current.plywo_execution_id
        return yield if execution_id.nil?

        ExecutionWorkLifecycle.running(self)
        result = DurableEvidenceBuffer.capture(
          execution_id:,
          producer_kind: "active_job",
          producer_name: self.class.name,
          producer_id: job_id
        ) { yield }
        ExecutionWorkLifecycle.completed(self)
        result
      rescue StandardError => error
        ExecutionWorkLifecycle.failed(self, error:)
        raise
      end
    end
  end
end
