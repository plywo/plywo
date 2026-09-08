require "fileutils"
require "net/http"
require "pathname"
require "socket"
require "timeout"
require "tmpdir"
require "uri"

module Plywo
  module Subject
    class ServiceExecutor
      Error = Class.new(StandardError)

      SAFE_INHERITED_ENV_KEYS = %w[
        PATH
        HOME
        TMPDIR
        LANG
        LC_ALL
        LC_CTYPE
        SSL_CERT_FILE
        SSL_CERT_DIR
      ].freeze
      SUPPORTED_START_OPERATION = "process.start".freeze
      SUPPORTED_HEALTHCHECK_OPERATION = "http.wait_ready".freeze
      SUPPORTED_STOP_OPERATION = "process.stop".freeze
      STOP_TIMEOUT_SECONDS = 2
      READINESS_INTERVAL_SECONDS = 0.05

      RunningService = Data.define(
        :name,
        :pid,
        :url_env,
        :url,
        :stdout_path,
        :stderr_path
      )
      Session = Data.define(:services, :state_dir)
      StartResult = Data.define(:session, :env)

      def initialize(host_env: ENV)
        @host_env = host_env
      end

      def start(root:, execution:, role:, env:, setup_plan:)
        steps = setup_plan&.steps_for("start_services") || []
        return StartResult.new(session: nil, env: {}) if steps.empty?

        state_dir = Pathname(Dir.mktmpdir("plywo-services-#{role}-"))
        running = []
        capture_env = {}

        steps.each do |step|
          unless step.operation == SUPPORTED_START_OPERATION
            raise Error, "Unsupported service start operation #{step.operation.inspect}"
          end

          service = start_process(
            root: Pathname(root),
            env: env.merge(capture_env),
            step:,
            state_dir:
          )
          running << service
          capture_env[service.url_env] = service.url
        end

        StartResult.new(
          session: Session.new(services: running.freeze, state_dir:),
          env: capture_env.freeze
        )
      rescue StandardError
        stop_session(Session.new(services: running.freeze, state_dir:)) if state_dir
        raise
      end

      def healthcheck(root:, execution:, role:, env:, setup_plan:, session:)
        return unless session

        services = session.services.each_with_object({}) do |service, result|
          result[service.name] = service
        end
        setup_plan.steps_for("healthcheck").each do |step|
          unless step.operation == SUPPORTED_HEALTHCHECK_OPERATION
            raise Error, "Unsupported service healthcheck operation #{step.operation.inspect}"
          end

          service_name = step.details.fetch("name")
          service = services.fetch(service_name) do
            raise Error, "Readiness references service that was not started: #{service_name}"
          end
          wait_until_ready(service:, step:, env:)
        end
      end

      def stop(root:, execution:, role:, env:, setup_plan:, session:)
        return unless session

        validation_error = nil
        begin
          validate_stop_steps!(setup_plan:, session:)
        rescue StandardError => error
          validation_error = error
        ensure
          stop_session(session)
        end

        raise validation_error if validation_error
      end

      private

      def start_process(root:, env:, step:, state_dir:)
        details = step.details
        name = details.fetch("name")
        command = details.fetch("command")
        port_env = details.fetch("port_env")
        url_env = details.fetch("url_env")
        port = allocate_port
        url = "http://127.0.0.1:#{port}"
        service_env = safe_inherited_environment.merge(env).merge(
          port_env => port.to_s,
          url_env => url
        )
        stdout_path = state_dir.join("#{name}.stdout.log")
        stderr_path = state_dir.join("#{name}.stderr.log")

        pid = Process.spawn(
          service_env,
          *command,
          chdir: root.to_s,
          out: stdout_path.to_s,
          err: stderr_path.to_s,
          unsetenv_others: true
        )

        RunningService.new(
          name:,
          pid:,
          url_env:,
          url:,
          stdout_path:,
          stderr_path:
        )
      rescue SystemCallError => error
        raise Error, "Could not start service #{name.inspect}: #{error.message}"
      end

      def wait_until_ready(service:, step:, env:)
        details = step.details
        path = details.fetch("path")
        timeout_seconds = details.fetch("timeout_seconds")
        url = env.fetch(details.fetch("url_env"), service.url)
        uri = URI("#{url}#{path}")
        deadline = monotonic_now + timeout_seconds
        last_error = nil

        loop do
          begin
            response = Net::HTTP.start(
              uri.host,
              uri.port,
              open_timeout: 0.5,
              read_timeout: 0.5
            ) { |http| http.get(uri.request_uri) }
            return if response.code.to_i.between?(200, 299)

            last_error = "status=#{response.code} body=#{response.body.to_s.inspect}"
          rescue SystemCallError, IOError, Timeout::Error => error
            last_error = "#{error.class}: #{error.message}"
          end

          break if monotonic_now >= deadline

          sleep READINESS_INTERVAL_SECONDS
        end

        raise Error,
          "Service #{service.name.inspect} failed readiness at #{uri}: #{last_error}; " \
          "stderr=#{tail(service.stderr_path).inspect}"
      end

      def validate_stop_steps!(setup_plan:, session:)
        steps = setup_plan.steps_for("stop_services")
        steps.each do |step|
          unless step.operation == SUPPORTED_STOP_OPERATION
            raise Error, "Unsupported service stop operation #{step.operation.inspect}"
          end
        end

        planned_names = steps.map { |step| step.details.fetch("name") }.sort
        running_names = session.services.map(&:name).sort
        return if planned_names == running_names

        raise Error,
          "Service stop plan does not match running services: " \
          "planned=#{planned_names.inspect} running=#{running_names.inspect}"
      end

      def stop_session(session)
        session.services.reverse_each { |service| stop_process(service) }
        FileUtils.rm_rf(session.state_dir)
      end

      def stop_process(service)
        Process.kill("TERM", service.pid)
        Timeout.timeout(STOP_TIMEOUT_SECONDS) { Process.wait(service.pid) }
      rescue Errno::ESRCH, Errno::ECHILD
        nil
      rescue Timeout::Error
        begin
          Process.kill("KILL", service.pid)
        rescue Errno::ESRCH
          nil
        end
        begin
          Process.wait(service.pid)
        rescue Errno::ECHILD
          nil
        end
      end

      def allocate_port
        server = TCPServer.new("127.0.0.1", 0)
        server.addr[1]
      ensure
        server&.close
      end

      def safe_inherited_environment
        SAFE_INHERITED_ENV_KEYS.each_with_object({}) do |key, environment|
          value = @host_env[key]
          environment[key] = value if value
        end
      end

      def tail(path, bytes: 2_000)
        return "" unless path.file?

        content = path.read
        content.bytesize > bytes ? content.byteslice(-bytes, bytes) : content
      rescue StandardError
        ""
      end

      def monotonic_now
        Process.clock_gettime(Process::CLOCK_MONOTONIC)
      end
    end
  end
end
