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

        plan = with_explicit_services(plans.first, configuration:)
        with_executor_capabilities(plan)
      end

      private

      def with_explicit_services(plan, configuration:)
        services = configuration.services
        return plan if services.empty?

        SetupPlan.new(
          framework: plan.framework,
          steps: plan.steps + services.flat_map { |service| service_steps(service) },
          evidence: plan.evidence.merge(
            "explicit_services" => services.map(&:name)
          )
        )
      end

      def service_steps(service)
        [
          {
            phase: "start_services",
            operation: "process.start",
            provenance: "explicit",
            details: {
              name: service.name,
              runtime: service.runtime,
              entrypoint: service.entrypoint,
              args: service.args,
              port_env: service.port_env,
              url_env: service.url_env
            }
          },
          {
            phase: "healthcheck",
            operation: "http.wait_ready",
            provenance: "explicit",
            details: {
              name: service.name,
              url_env: service.url_env,
              path: service.readiness.path,
              timeout_seconds: service.readiness.timeout_seconds
            }
          },
          {
            phase: "stop_services",
            operation: "process.stop",
            provenance: "explicit",
            details: {
              name: service.name
            }
          }
        ]
      end

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
