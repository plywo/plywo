#!/usr/bin/env ruby

require "active_support/core_ext/object/blank"
require "fileutils"
require "net/http"
require "pathname"
require "rbconfig"
require "tmpdir"
require "timeout"
require "uri"

TOOL_ROOT = Pathname(__dir__).join("..").expand_path.freeze

require TOOL_ROOT.join("lib", "plywo", "subject", "environment").to_s
require TOOL_ROOT.join("lib", "plywo", "subject", "lifecycle").to_s

module HttpServiceLifecycleProof
  Configuration = Data.define(:capture_env)

  class HttpServiceEnvironment < Plywo::Subject::Environment
    attr_reader :cleanup_count, :last_pid, :service_url, :state_dir, :stop_count

    def initialize(status:)
      @status = status
      @cleanup_count = 0
      @stop_count = 0
    end

    def prepare(root:, execution:, role:)
      @state_dir = Pathname(Dir.mktmpdir("plywo-http-service-#{role}-"))
      {
        "PLYWO_HTTP_SERVICE_STATE_DIR" => @state_dir.to_s
      }
    end

    def env_for(root:, execution:, role:)
      {}
    end

    def start_services(root:, execution:, role:, env:)
      reader, writer = IO.pipe
      child_code = <<~RUBY
        require "socket"

        STDOUT.sync = true
        status = #{@status}
        server = TCPServer.new("127.0.0.1", 0)
        puts server.addr[1]

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
            response =
              "HTTP/1.1 " + status.to_s + " " + reason + "\\r\\n" +
              "Content-Type: text/plain\\r\\n" +
              "Content-Length: " + body.bytesize.to_s + "\\r\\n" +
              "Connection: close\\r\\n\\r\\n" +
              body
            client.write(response)
          ensure
            client.close rescue nil
          end
        end
      RUBY

      stderr_path = @state_dir.join("service.stderr")
      @last_pid = Process.spawn(
        RbConfig.ruby,
        "-e",
        child_code,
        out: writer,
        err: stderr_path.to_s
      )
      writer.close

      port_line = Timeout.timeout(5) { reader.gets }
      reader.close
      raise "HTTP service exited before publishing its dynamic port" unless port_line

      port = Integer(port_line.strip, 10)
      @service_url = "http://127.0.0.1:#{port}/health"
      env["PLYWO_HTTP_SERVICE_URL"] = @service_url
      @state_dir.join("service.pid").write("#{@last_pid}\n")
      @state_dir.join("service.url").write("#{@service_url}\n")
    ensure
      writer&.close unless writer&.closed?
      reader&.close unless reader&.closed?
    end

    def healthcheck(root:, execution:, role:, env:)
      uri = URI(env.fetch("PLYWO_HTTP_SERVICE_URL"))
      response = Net::HTTP.start(
        uri.host,
        uri.port,
        open_timeout: 1,
        read_timeout: 1
      ) { |http| http.get(uri.request_uri) }
      return if response.code == "200" && response.body == "OK"

      raise "HTTP service readiness failed: status=#{response.code} body=#{response.body.inspect}"
    end

    def stop_services(root:, execution:, role:, env:)
      @stop_count += 1
      return unless @last_pid

      begin
        Process.kill("TERM", @last_pid)
      rescue Errno::ESRCH
        return
      end

      begin
        Timeout.timeout(2) { Process.wait(@last_pid) }
      rescue Timeout::Error
        Process.kill("KILL", @last_pid) rescue nil
        Process.wait(@last_pid) rescue nil
      rescue Errno::ECHILD
        nil
      end
    end

    def cleanup(root:, execution:, role:)
      @cleanup_count += 1
      FileUtils.rm_rf(@state_dir) if @state_dir
    end

    def process_alive?
      return false unless @last_pid

      Process.kill(0, @last_pid)
      true
    rescue Errno::ESRCH
      false
    rescue Errno::EPERM
      true
    end
  end

  module_function

  def call
    success = prove_success_path
    failure = prove_readiness_failure_path

    puts "HTTP subject service lifecycle proof"
    puts "dynamic_port_assigned=true"
    puts "readiness_before_capture=true"
    puts "capture_service_response=#{success.fetch(:body)}"
    puts "success_service_stopped=#{!success.fetch(:environment).process_alive?}"
    puts "success_state_cleaned=#{!success.fetch(:state_dir).exist?}"
    puts "readiness_failure_capture_skipped=#{!failure.fetch(:capture_ran)}"
    puts "readiness_failure_service_stopped=#{!failure.fetch(:environment).process_alive?}"
    puts "readiness_failure_state_cleaned=#{!failure.fetch(:state_dir).exist?}"
    puts "teardown_order=stop_services_then_cleanup"
  end

  def prove_success_path
    environment = HttpServiceEnvironment.new(status: 200)
    lifecycle = lifecycle_for(environment)
    capture_ran = false
    body = nil
    state_dir = nil

    lifecycle.open(
      root: TOOL_ROOT,
      execution: Object.new,
      role: "baseline",
      configuration: Configuration.new(capture_env: {})
    ) do |session|
      capture_ran = true
      state_dir = Pathname(session.env.fetch("PLYWO_HTTP_SERVICE_STATE_DIR"))
      raise "Service state must exist during capture" unless state_dir.directory?

      uri = URI(session.env.fetch("PLYWO_HTTP_SERVICE_URL"))
      response = Net::HTTP.get_response(uri)
      raise "Expected healthy HTTP service during capture" unless response.code == "200"

      body = response.body
      raise "Unexpected HTTP service response #{body.inspect}" unless body == "OK"
    end

    raise "Lifecycle capture did not run after readiness" unless capture_ran
    raise "HTTP service remained alive after successful capture" if environment.process_alive?
    raise "Expected one service stop after successful capture" unless environment.stop_count == 1
    raise "Expected one cleanup after successful capture" unless environment.cleanup_count == 1
    raise "Service state survived cleanup" if state_dir.exist?

    { environment:, state_dir:, body: }
  end

  def prove_readiness_failure_path
    environment = HttpServiceEnvironment.new(status: 503)
    lifecycle = lifecycle_for(environment)
    capture_ran = false
    error = nil

    begin
      lifecycle.open(
        root: TOOL_ROOT,
        execution: Object.new,
        role: "candidate",
        configuration: Configuration.new(capture_env: {})
      ) do
        capture_ran = true
      end
    rescue RuntimeError => exception
      error = exception
    end

    raise "Expected readiness failure" unless error&.message&.start_with?("HTTP service readiness failed:")
    raise "Capture ran despite failed readiness" if capture_ran
    raise "HTTP service remained alive after readiness failure" if environment.process_alive?
    raise "Expected one service stop after readiness failure" unless environment.stop_count == 1
    raise "Expected one cleanup after readiness failure" unless environment.cleanup_count == 1
    raise "Service state survived readiness-failure cleanup" if environment.state_dir.exist?

    { environment:, state_dir: environment.state_dir, capture_ran: }
  end

  def lifecycle_for(environment)
    Plywo::Subject::Lifecycle.new(discovery: nil, environment:)
  end
end

HttpServiceLifecycleProof.call
