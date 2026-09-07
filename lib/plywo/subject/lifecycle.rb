module Plywo
  module Subject
    class Lifecycle
      Session = Data.define(:environment, :env)

      def initialize(discovery:, bootstrap: nil, environment: nil)
        @discovery = discovery
        @bootstrap = bootstrap
        @environment = environment
      end

      def open(root:, execution:, role:, configuration:)
        runtime_env = bootstrap(root:)
        environment = resolve_environment(root:, configuration:, runtime_env:)
        capture_env = nil
        services_started = false

        begin
          capture_env = environment.prepare(root:, execution:, role:).merge(configuration.capture_env)
          services_started = true
          environment.start_services(root:, execution:, role:, env: capture_env)
          environment.healthcheck(root:, execution:, role:, env: capture_env)

          yield Session.new(environment:, env: capture_env)
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

      def bootstrap(root:)
        return {} unless @bootstrap

        @bootstrap.call(root:)
      end

      def resolve_environment(root:, configuration:, runtime_env:)
        return @environment if @environment

        @discovery.resolve(root:, configuration:, runtime_env:)
      end
    end
  end
end
