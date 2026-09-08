require "test_helper"
require "net/http"
require "tmpdir"
require "uri"

class PlywoSubjectServiceExecutorTest < ActiveSupport::TestCase
  test "starts process on a dynamic port, waits for HTTP readiness, and tears it down" do
    Dir.mktmpdir("plywo-service-executor-") do |directory|
      root = Pathname(directory)
      write_service(root, status: 200)
      plan = setup_plan
      executor = Plywo::Subject::ServiceExecutor.new
      result = executor.start(
        root:,
        execution: Object.new,
        role: "candidate",
        env: {},
        setup_plan: plan
      )
      session = result.session
      service = session.services.fetch(0)
      url = result.env.fetch("MOCK_API_URL")

      assert_match(%r{\Ahttp://127\.0\.0\.1:\d+\z}, url)
      assert_equal url, service.url
      assert session.state_dir.directory?

      capture_env = result.env.dup
      executor.healthcheck(
        root:,
        execution: Object.new,
        role: "candidate",
        env: capture_env,
        setup_plan: plan,
        session:
      )

      response = Net::HTTP.get_response(URI("#{url}/health"))
      assert_equal "200", response.code
      assert_equal "OK", response.body

      executor.stop(
        root:,
        execution: Object.new,
        role: "candidate",
        env: capture_env,
        setup_plan: plan,
        session:
      )

      refute session.state_dir.exist?
      assert_raises(Errno::ESRCH) { Process.kill(0, service.pid) }
    end
  end

  test "reports readiness failure with service context" do
    Dir.mktmpdir("plywo-service-executor-") do |directory|
      root = Pathname(directory)
      write_service(root, status: 503)
      plan = setup_plan(timeout_seconds: 1)
      executor = Plywo::Subject::ServiceExecutor.new
      result = executor.start(
        root:,
        execution: Object.new,
        role: "candidate",
        env: {},
        setup_plan: plan
      )

      error = assert_raises(Plywo::Subject::ServiceExecutor::Error) do
        executor.healthcheck(
          root:,
          execution: Object.new,
          role: "candidate",
          env: result.env,
          setup_plan: plan,
          session: result.session
        )
      end

      assert_includes error.message, "mock-api"
      assert_includes error.message, "status=503"
    ensure
      executor&.stop(
        root: root || Pathname(directory),
        execution: Object.new,
        role: "candidate",
        env: result&.env || {},
        setup_plan: plan,
        session: result&.session
      ) if result&.session
    end
  end

  private

  def setup_plan(timeout_seconds: 2)
    Plywo::Subject::SetupPlan.new(
      framework: "test",
      steps: [
        {
          phase: "start_services",
          operation: "process.start",
          provenance: "explicit",
          details: {
            name: "mock-api",
            command: [ "ruby", "service.rb" ],
            port_env: "MOCK_API_PORT",
            url_env: "MOCK_API_URL"
          }
        },
        {
          phase: "healthcheck",
          operation: "http.wait_ready",
          provenance: "explicit",
          details: {
            name: "mock-api",
            url_env: "MOCK_API_URL",
            path: "/health",
            timeout_seconds:
          }
        },
        {
          phase: "stop_services",
          operation: "process.stop",
          provenance: "explicit",
          details: { name: "mock-api" }
        }
      ]
    )
  end

  def write_service(root, status:)
    root.join("service.rb").write(<<~RUBY)
      require "socket"

      status = #{status}
      server = TCPServer.new("127.0.0.1", Integer(ENV.fetch("MOCK_API_PORT"), 10))
      trap("TERM") do
        server.close rescue nil
        exit! 0
      end

      loop do
        client = server.accept
        begin
          while (line = client.gets)
            break if line == "\\r\\n"
          end

          body = status == 200 ? "OK" : "NOT READY"
          reason = status == 200 ? "OK" : "Service Unavailable"
          client.write(
            "HTTP/1.1 " + status.to_s + " " + reason + "\\r\\n" +
            "Content-Type: text/plain\\r\\n" +
            "Content-Length: " + body.bytesize.to_s + "\\r\\n" +
            "Connection: close\\r\\n\\r\\n" +
            body
          )
        ensure
          client.close rescue nil
        end
      end
    RUBY
  end
end
