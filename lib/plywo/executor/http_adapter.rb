require "json"
require "net/http"
require "uri"

module Plywo
  module Executor
    class HttpAdapter
      Error = Class.new(StandardError)
      Response = Data.define(:status, :body)

      DEFAULT_OPEN_TIMEOUT_SECONDS = 5
      DEFAULT_READ_TIMEOUT_SECONDS = 2_100

      class NetHttpTransport
        def call(uri:, headers:, body:, open_timeout:, read_timeout:)
          request = Net::HTTP::Post.new(uri)
          headers.each { |name, value| request[name] = value }
          request.body = body

          response = Net::HTTP.start(
            uri.host,
            uri.port,
            use_ssl: uri.scheme == "https",
            open_timeout:,
            read_timeout:
          ) do |http|
            http.request(request)
          end

          Response.new(status: Integer(response.code), body: response.body.to_s)
        end
      end

      def initialize(
        url:,
        token:,
        open_timeout: DEFAULT_OPEN_TIMEOUT_SECONDS,
        read_timeout: DEFAULT_READ_TIMEOUT_SECONDS,
        transport: NetHttpTransport.new
      )
        @uri = URI.parse(url)
        @token = token.to_s
        @open_timeout = Integer(open_timeout)
        @read_timeout = Integer(read_timeout)
        @transport = transport

        validate_configuration!
      end

      def call(request:)
        response = @transport.call(
          uri: @uri,
          headers: headers(request:),
          body: JSON.generate(request.to_h),
          open_timeout: @open_timeout,
          read_timeout: @read_timeout
        )

        unless response.status.between?(200, 299)
          raise Error, "Remote executor returned HTTP #{response.status}"
        end

        payload = JSON.parse(response.body)
        raise Error, "Remote executor result must be a JSON object" unless payload.is_a?(Hash)

        Result.from_h(payload)
      rescue JSON::ParserError => error
        raise Error, "Remote executor returned invalid JSON: #{error.message}"
      rescue KeyError, ArgumentError => error
        raise Error, "Remote executor returned an invalid result: #{error.message}"
      end

      private

      def validate_configuration!
        raise Error, "Remote executor URL must use http or https" unless %w[http https].include?(@uri.scheme)
        raise Error, "Remote executor URL must include a host" if @uri.host.to_s.empty?
        raise Error, "Remote executor token is required" if @token.empty?
        raise Error, "Remote executor open timeout must be positive" unless @open_timeout.positive?
        raise Error, "Remote executor read timeout must be positive" unless @read_timeout.positive?
      end

      def headers(request:)
        {
          "Accept" => "application/json",
          "Authorization" => "Bearer #{@token}",
          "Content-Type" => "application/json",
          "Idempotency-Key" => "#{request.execution_id}:#{request.attempt_number}"
        }
      end
    end
  end
end
