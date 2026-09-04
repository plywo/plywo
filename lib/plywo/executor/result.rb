module Plywo
  module Executor
    Result = Data.define(
      :schema_version,
      :status,
      :payload,
      :error_class,
      :error_message
    ) do
      SCHEMA_VERSION = "1".freeze
      STATUSES = %w[succeeded failed].freeze

      def self.success(payload)
        new(
          schema_version: SCHEMA_VERSION,
          status: "succeeded",
          payload:,
          error_class: nil,
          error_message: nil
        )
      end

      def self.failure(error)
        new(
          schema_version: SCHEMA_VERSION,
          status: "failed",
          payload: nil,
          error_class: error.class.to_s,
          error_message: error.message.to_s
        )
      end

      def self.from_h(payload)
        payload = payload.transform_keys(&:to_s)
        schema_version = payload.fetch("schema_version")
        raise ArgumentError, "Unsupported executor result schema #{schema_version.inspect}" unless schema_version == SCHEMA_VERSION

        status = payload.fetch("status")
        raise ArgumentError, "Unsupported executor result status #{status.inspect}" unless STATUSES.include?(status)

        new(
          schema_version:,
          status:,
          payload: payload["payload"],
          error_class: payload["error_class"],
          error_message: payload["error_message"]
        )
      end

      def success?
        status == "succeeded"
      end

      def failure?
        status == "failed"
      end

      def to_h
        {
          "schema_version" => schema_version,
          "status" => status,
          "payload" => payload,
          "error_class" => error_class,
          "error_message" => error_message
        }
      end
    end
  end
end
