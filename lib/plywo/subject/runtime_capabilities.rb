module Plywo
  module Subject
    class RuntimeCapabilities
      Error = Class.new(ArgumentError)

      attr_reader :runtimes, :package_managers

      def self.ruby_only(version: RUBY_VERSION)
        new(runtimes: { "ruby" => version }, package_managers: {})
      end

      def initialize(runtimes:, package_managers:)
        @runtimes = normalize_mapping(runtimes, kind: "runtime").freeze
        @package_managers = normalize_mapping(package_managers, kind: "package manager").freeze
      end

      def runtime?(name)
        runtimes.key?(name.to_s)
      end

      def package_manager?(name)
        package_managers.key?(name.to_s)
      end

      def runtime_version(name)
        runtimes[name.to_s]
      end

      def package_manager_version(name)
        package_managers[name.to_s]
      end

      def to_h
        {
          "runtimes" => runtimes,
          "package_managers" => package_managers
        }
      end

      private

      def normalize_mapping(value, kind:)
        unless value.is_a?(Hash)
          raise Error, "Executor #{kind} capabilities must be a mapping"
        end

        value.each_with_object({}) do |(name, version), result|
          name = name.to_s.strip
          version = version.to_s.strip
          raise Error, "Executor #{kind} capability name must not be empty" if name.empty?
          raise Error, "Executor #{kind} capability #{name.inspect} must declare a version" if version.empty?

          result[name] = version
        end
      end
    end
  end
end
