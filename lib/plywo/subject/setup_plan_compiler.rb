module Plywo
  module Subject
    class SetupPlanCompiler
      Error = Class.new(StandardError)

      def initialize(detectors: [ RailsSetupPlanDetector.new ])
        @detectors = detectors.freeze
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

        plans.first
      end
    end
  end
end
