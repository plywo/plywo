require "json"
require "pathname"
require "tmpdir"

require_relative "../config/environment"

identity = Plywo::Subject::ExecutionIdentity.from_env
raise "subject execution identity is disabled" unless identity.enabled?

Dir.mktmpdir("plywo-subject-privilege-") do |directory|
  root = Pathname(directory)
  workspace = root.join("workspace")
  workspace.mkdir

  secret = root.join("provider-authority.txt")
  secret.write("provider-authority")
  secret.chmod(0o600)

  probe = workspace.join("probe.rb")
  probe.write(<<~RUBY)
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

  puts "subject_privilege_boundary=ok"
  puts "subject_uid=#{identity.uid}"
  puts "subject_gid=#{identity.gid}"
  puts "provider_authority_readable=false"
end
