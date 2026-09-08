module Plywo
  module Subject
    class Lifecycle
      Session = Data.define(:environment, :env, :setup_plan)

      def initialize(discovery:, bootstrap: nil, environment: nil, setup_plan_compiler: nil)
        @discovery = discovery
        @bootstrap = bootstrap
        @environment = environment
        @setup_plan_compiler = setup_plan_compiler
      end

      def open(root:, execution:, role:, configuration:, setup_configuration: configuration)
        setup_plan = compile_setup_plan(root:, configuration: setup_configuration)
        runtime_env = bootstrap(root:, setup_plan:)
        environment = resolve_environment(root:, configuration: setup_configuration, runtime_env:)
        capture_env = nil
        services_started = false

        begin
          capture_env = environment.prepare(root:, execution:, role:).merge(configuration.capture_env)
          services_started = true
          environment.start_services(root:, execution:, role:, env: capture_env)
          environment.healthcheck(root:, execution:, role:, env: capture_env)

          yield Session.new(environment:, env: capture_env, setup_plan:)
        ensure
          if services_started
            begin
              environment.stop_services(root:, execution:, role:, env: capture_env)
            ensure
              environment.cleanup(root:, execution:, role:)
            end
          else
            environment.cleanup(root:, execution:, role:)
          end
        end
      end

      private

      def compile_setup_plan(root:, configuration:)
        return unless @setup_plan_compiler

        @setup_plan_compiler.call(root:, configuration:)
      end

      def bootstrap(root:, setup_plan:)
        return {} unless @bootstrap

        @bootstrap.call(root:, setup_plan:)
      end

      def resolve_environment(root:, configuration:, runtime_env:)
        return @environment if @environment

        @discovery.resolve(root:, configuration:, runtime_env:)
      end
    end
  end
end
