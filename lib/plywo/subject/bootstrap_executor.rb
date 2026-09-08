module Plywo
  module Subject
    class BootstrapExecutor
      Error = Class.new(StandardError)

      def initialize(ruby_bundle_bootstrap:)
        @ruby_bundle_bootstrap = ruby_bundle_bootstrap
      end

      def call(root:, setup_plan:)
        raise Error, "Subject setup plan is required for bootstrap execution" unless setup_plan

        setup_plan.steps_for("bootstrap").each_with_object({}) do |step, environment|
          step_environment = execute_step(root:, step:)
          merge_environment!(environment, step_environment, operation: step.operation)
        end
      end

      private

      def execute_step(root:, step:)
        case step.operation
        when "ruby.bundle"
          assert_ruby_bundle_step!(step)
          @ruby_bundle_bootstrap.call(root:)
        when "javascript.dependencies"
          raise Error,
            "Unsupported bootstrap operation javascript.dependencies: " \
            "executor does not provide a JavaScript runtime/package-manager capability yet"
        else
          raise Error, "Unsupported bootstrap operation #{step.operation.inspect}"
        end
      end

      def assert_ruby_bundle_step!(step)
        manifest = step.details.fetch("manifest", nil)
        lockfile = step.details.fetch("lockfile", nil)
        return if manifest == "Gemfile" && lockfile == "Gemfile.lock"

        raise Error,
          "ruby.bundle setup step must use Gemfile and Gemfile.lock; " \
          "received manifest=#{manifest.inspect} lockfile=#{lockfile.inspect}"
      end

      def merge_environment!(environment, addition, operation:)
        unless addition.is_a?(Hash)
          raise Error, "Bootstrap operation #{operation.inspect} must return an environment mapping"
        end

        addition.each do |key, value|
          key = key.to_s
          if environment.key?(key) && environment.fetch(key) != value
            raise Error, "Bootstrap operations produced conflicting values for environment key #{key.inspect}"
          end

          environment[key] = value
        end
      end
    end
  end
end
