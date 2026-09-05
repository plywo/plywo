module Plywo
  module Subject
    class Environment
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
