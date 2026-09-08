require "json"
require "net/http"
require "pathname"
require "tmpdir"
require "uri"

require_relative "../config/environment"

identity = Plywo::Subject::ExecutionIdentity.from_env
raise "subject execution identity is disabled" unless identity.enabled?

Dir.mktmpdir("plywo-subject-privilege-") do |directory|
  root = Pathname(directory)
  root.chmod(0o711)
  workspace = root.join("workspace")
  workspace.mkdir

  secret = root.join("provider-authority.txt")
  secret.write("provider-authority")
  secret.chmod(0o600)

  probe = workspace.join("probe.rb")
  probe.write(<<~'RUBY')
    require "json"

    secret_path = ARGV.fetch(0)
    secret_readable = begin
      File.read(secret_path)
      true
    rescue Errno::EACCES, Errno::EPERM
      false
    end

    puts JSON.generate(
      euid: Process.euid,
      egid: Process.egid,
      home: ENV["HOME"],
      user: ENV["USER"],
      logname: ENV["LOGNAME"],
      secret_readable: secret_readable
    )
  RUBY

  service = workspace.join("service.rb")
  service.write(<<~'RUBY')
    require "json"
    require "socket"

    secret_path = ARGV.fetch(0)
    secret_readable = begin
      File.read(secret_path)
      true
    rescue Errno::EACCES, Errno::EPERM
      false
    end

    body = JSON.generate(
      euid: Process.euid,
      egid: Process.egid,
      home: ENV["HOME"],
      user: ENV["USER"],
      secret_readable: secret_readable
    )
    server = TCPServer.new("127.0.0.1", Integer(ENV.fetch("SERVICE_PORT"), 10))

    trap("TERM") do
      server.close
      exit
    end

    loop do
      socket = server.accept
      request_line = socket.gets.to_s
      loop do
        header = socket.gets
        break if header.nil? || header == "\r\n"
      end
      response_body = request_line.include?("/health") ? body : "not-found"
      status = request_line.include?("/health") ? "200 OK" : "404 Not Found"
      socket.write("HTTP/1.1 #{status}\r\nContent-Length: #{response_body.bytesize}\r\nConnection: close\r\n\r\n#{response_body}")
      socket.close
    end
  RUBY

  identity.prepare_tree(workspace)

  runner = Plywo::Github::LocalPullRequestRunner::CommandRunner.new(
    execution_identity: identity
  )
  output = runner.call(
    env: {
      "HOME" => "/root",
      "USER" => "root",
      "LOGNAME" => "root"
    },
    command: [ RbConfig.ruby, probe.to_s, secret.to_s ],
    chdir: workspace.to_s
  )
  result = JSON.parse(output)

  raise "subject runtime uid mismatch: #{result.inspect}" unless result.fetch("euid") == identity.uid
  raise "subject runtime gid mismatch: #{result.inspect}" unless result.fetch("egid") == identity.gid
  raise "subject HOME was overrideable: #{result.inspect}" unless result.fetch("home") == identity.home
  raise "subject USER was overrideable: #{result.inspect}" unless result.fetch("user") == identity.user
  raise "subject LOGNAME was overrideable: #{result.inspect}" unless result.fetch("logname") == identity.user
  raise "subject runtime could read provider authority material" if result.fetch("secret_readable")

  plan = Plywo::Subject::SetupPlan.new(
    framework: "rails",
    steps: [
      {
        phase: "start_services",
        operation: "process.start",
        provenance: "explicit",
        details: {
          name: "privilege-proof",
          runtime: "ruby",
          entrypoint: "service.rb",
          args: [ secret.to_s ],
          port_env: "SERVICE_PORT",
          url_env: "SERVICE_URL"
        }
      },
      {
        phase: "healthcheck",
        operation: "http.wait_ready",
        provenance: "explicit",
        details: {
          name: "privilege-proof",
          url_env: "SERVICE_URL",
          path: "/health",
          timeout_seconds: 5
        }
      },
      {
        phase: "stop_services",
        operation: "process.stop",
        provenance: "explicit",
        details: { name: "privilege-proof" }
      }
    ]
  )
  executor = Plywo::Subject::ServiceExecutor.new(execution_identity: identity)
  started = executor.start(
    root: workspace,
    execution: nil,
    role: "privilege-proof",
    env: {},
    setup_plan: plan
  )

  begin
    env = started.env
    executor.healthcheck(
      root: workspace,
      execution: nil,
      role: "privilege-proof",
      env:,
      setup_plan: plan,
      session: started.session
    )

    uri = URI(env.fetch("SERVICE_URL") + "/health")
    service_result = JSON.parse(Net::HTTP.get(uri))
    raise "service runtime uid mismatch: #{service_result.inspect}" unless service_result.fetch("euid") == identity.uid
    raise "service runtime gid mismatch: #{service_result.inspect}" unless service_result.fetch("egid") == identity.gid
    raise "service HOME mismatch: #{service_result.inspect}" unless service_result.fetch("home") == identity.home
    raise "service USER mismatch: #{service_result.inspect}" unless service_result.fetch("user") == identity.user
    raise "service runtime could read provider authority material" if service_result.fetch("secret_readable")
  ensure
    executor.stop(
      root: workspace,
      execution: nil,
      role: "privilege-proof",
      env: started.env,
      setup_plan: plan,
      session: started.session
    )
  end

  puts "subject_privilege_boundary=ok"
  puts "subject_uid=#{identity.uid}"
  puts "subject_gid=#{identity.gid}"
  puts "capture_provider_authority_readable=false"
  puts "service_provider_authority_readable=false"
end
