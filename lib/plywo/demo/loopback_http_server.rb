require "socket"

module Plywo
  module Demo
    class LoopbackHttpServer
      RESPONSE = "HTTP/1.1 204 No Content\r\nConnection: close\r\nContent-Length: 0\r\n\r\n".freeze

      class << self
        def url(delay_ms: nil)
          start unless @server
          path = delay_ms ? "/ping?delay_ms=#{Integer(delay_ms)}" : "/ping"
          "http://127.0.0.1:#{@server.addr[1]}#{path}"
        end

        private

        def start
          @server = TCPServer.new("127.0.0.1", 0)
          @thread = Thread.new do
            loop do
              client = @server.accept
              serve(client)
            end
          rescue IOError, Errno::EBADF
            nil
          end
          at_exit { stop }
        end

        def serve(client)
          request_line = client.gets
          while (line = client.gets)
            break if line == "\r\n"
          end

          sleep(delay_seconds(request_line))
          client.write(RESPONSE)
        ensure
          client.close
        end

        def delay_seconds(request_line)
          delay_ms = request_line.to_s[/[?&]delay_ms=(\d+)/, 1]
          delay_ms ? Integer(delay_ms) / 1000.0 : 0.0
        end

        def stop
          @server&.close
          @thread&.kill
        end
      end
    end
  end
end
