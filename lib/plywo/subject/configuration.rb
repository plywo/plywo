require "pathname"
require "yaml"

module Plywo
  module Subject
    class Configuration
      Error = Class.new(StandardError)

      CURRENT_VERSION = 1
      DEFAULT_PERSISTENCE = "auto".freeze
      PERSISTENCE_VALUES = %w[auto postgresql sqlite].freeze
      TOP_LEVEL_KEYS = %w[version scenario subject].freeze
      SCENARIO_KEYS = %w[path].freeze
      SUBJECT_KEYS = %w[persistence].freeze

      attr_reader :scenario_path, :persistence, :source_path

      def self.load(root:)
        path = Pathname(root).join("plywo.yml")
        return new(scenario_path: nil, persistence: DEFAULT_PERSISTENCE, source_path: nil) unless path.file?

        payload = YAML.safe_load(path.read, permitted_classes: [], permitted_symbols: [], aliases: false) || {}
        validate_mapping!(payload, name: "plywo.yml", allowed_keys: TOP_LEVEL_KEYS)

        version = payload.fetch("version") { raise Error, "plywo.yml must declare version: #{CURRENT_VERSION}" }
        raise Error, "Unsupported plywo.yml version #{version.inspect}" unless version == CURRENT_VERSION

        scenario = payload.fetch("scenario", {}) || {}
        subject = payload.fetch("subject", {}) || {}
        validate_mapping!(scenario, name: "scenario", allowed_keys: SCENARIO_KEYS)
        validate_mapping!(subject, name: "subject", allowed_keys: SUBJECT_KEYS)

        scenario_path = scenario["path"]
        validate_scenario_path!(scenario_path)

        persistence = subject.fetch("persistence", DEFAULT_PERSISTENCE).to_s
        unless PERSISTENCE_VALUES.include?(persistence)
          raise Error, "Unsupported subject.persistence #{persistence.inspect}; expected one of #{PERSISTENCE_VALUES.join(", ")}"
        end

        new(scenario_path:, persistence:, source_path: path)
      rescue Psych::Exception => error
        raise Error, "Invalid plywo.yml: #{error.message}"
      end

      def initialize(scenario_path:, persistence:, source_path:)
        @scenario_path = scenario_path
        @persistence = persistence
        @source_path = source_path
      end

      def capture_env
        return {} unless scenario_path

        { "PLYWO_SCENARIO_PATH" => scenario_path }
      end

      class << self
        private

        def validate_mapping!(value, name:, allowed_keys:)
          raise Error, "#{name} must be a mapping" unless value.is_a?(Hash)

          unknown_keys = value.keys.map(&:to_s) - allowed_keys
          return if unknown_keys.empty?

          raise Error, "Unknown #{name} keys: #{unknown_keys.sort.join(", ")}"
        end

        def validate_scenario_path!(path)
          return if path.nil?
          return if path.is_a?(String) && path.start_with?("/")

          raise Error, "scenario.path must be an absolute HTTP path starting with /"
        end
      end
    end
  end
end
