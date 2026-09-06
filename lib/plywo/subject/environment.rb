module Plywo
  module Subject
    class Environment
      EMPTY_CAPABILITIES = [].freeze

      def capabilities
        EMPTY_CAPABILITIES
      end

      def capability?(name)
        capabilities.include?(name.to_s)
      end

      def capabilities_for(namespace)
        prefix = "#{namespace}."

        capabilities.filter_map do |capability|
          capability.delete_prefix(prefix) if capability.start_with?(prefix)
        end
      end

      def prepare(root:, execution:, role:)
        raise NotImplementedError
      end

      def env_for(root:, execution:, role:)
        raise NotImplementedError
      end

      def cleanup(root:, execution:, role:)
        nil
      end
    end
  end
end
