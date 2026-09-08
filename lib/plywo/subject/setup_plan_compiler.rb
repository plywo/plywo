require "pathname"

module Plywo
  module Subject
    class SetupPlanCompiler
      Error = Class.new(StandardError)

      def initialize(detectors: [ RailsSetupPlanDetector.new ], runtime_capabilities: nil)
        @detectors = detectors.freeze
        @runtime_capabilities = runtime_capabilities
      end

      def call(root:, configuration:)
        plans = @detectors.filter_map do |detector|
          detector.call(root:, configuration:)
        end

        if plans.empty?
          raise Error, "Could not compile a subject setup plan for #{Pathname(root).expand_path}"
        end
        if plans.length > 1
          frameworks = plans.map(&:framework).sort.join(", ")
          raise Error, "Ambiguous subject setup plan for #{Pathname(root).expand_path}: #{frameworks}"
        end

        with_executor_capabilities(plans.first)
      end

      private

      def with_executor_capabilities(plan)
        return plan unless @runtime_capabilities

        SetupPlan.new(
          framework: plan.framework,
          steps: plan.steps,
          evidence: plan.evidence.merge(
            "executor_runtime_capabilities" => @runtime_capabilities.to_h
          )
        )
      end
    end
  end
end
