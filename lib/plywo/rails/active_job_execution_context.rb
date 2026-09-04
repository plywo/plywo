module Plywo
  module Rails
    module ActiveJobExecutionContext
      CONTEXT_KEY = "plywo_execution_context"
      CONTEXT_ATTRIBUTES = %w[plywo_execution_id plywo_run_id plywo_subject].freeze

      def self.included(base)
        base.around_perform do |job, block|
          job.send(:with_plywo_execution_context, &block)
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

      def with_plywo_execution_context
        context = @plywo_execution_context
        return yield if context.nil? || context.empty?

        Current.set(**context.transform_keys(&:to_sym)) { yield }
      end
    end
  end
end
