module Plywo
  module Runtime
    class Role
      Error = Class.new(StandardError)

      VALUES = %w[control_plane executor_service combined].freeze

      attr_reader :name

      def self.from_env(env: ENV, rails_env: ::Rails.env)
        explicit = env["PLYWO_RUNTIME_ROLE"].to_s
        name = if !explicit.empty?
          explicit
        elsif env["PLYWO_EXECUTOR_SERVICE"] == "1"
          "executor_service"
        elsif %w[development test].include?(rails_env.to_s)
          "combined"
        else
          "control_plane"
        end

        new(name)
      end

      def initialize(name)
        @name = name.to_s
        raise Error, "Unsupported PLYWO_RUNTIME_ROLE=#{@name.inspect}" unless VALUES.include?(@name)
      end

      def control_plane?
        name == "control_plane" || name == "combined"
      end

      def executor_service?
        name == "executor_service" || name == "combined"
      end

      def combined?
        name == "combined"
      end
    end
  end
end
