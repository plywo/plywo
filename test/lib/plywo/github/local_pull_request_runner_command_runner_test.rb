require "test_helper"
require "json"
require "rbconfig"

class PlywoGithubLocalPullRequestRunnerCommandRunnerTest < ActiveSupport::TestCase
  test "inherits only safe host variables and explicit command environment" do
    host_env = {
      "PATH" => ENV.fetch("PATH"),
      "HOME" => ENV.fetch("HOME", "/tmp"),
      "TMPDIR" => ENV.fetch("TMPDIR", "/tmp"),
      "LANG" => "en_US.UTF-8",
      "RUBYOPT" => "-rbootsnap/setup",
      "RUBYLIB" => "/private/plywo/ruby",
      "PLYWO_EXECUTOR_SERVICE_TOKEN" => "executor-secret",
      "PLYWO_GITHUB_WEBHOOK_SECRET" => "webhook-secret",
      "SSH_AUTH_SOCK" => "/private/ssh-agent.sock"
    }
    runner = Plywo::Github::LocalPullRequestRunner::CommandRunner.new(host_env:)
    keys = host_env.keys + [ "PLYWO_EXPLICIT_SENTINEL" ]
    script = "require 'json'; print JSON.generate(ENV.to_h.slice(*#{keys.inspect}))"

    output = runner.call(
      env: { "PLYWO_EXPLICIT_SENTINEL" => "visible" },
      command: [ RbConfig.ruby, "-e", script ],
      chdir: Rails.root.to_s
    )
    child_env = JSON.parse(output)

    assert_equal host_env.fetch("PATH"), child_env.fetch("PATH")
    assert_equal host_env.fetch("HOME"), child_env.fetch("HOME")
    assert_equal host_env.fetch("TMPDIR"), child_env.fetch("TMPDIR")
    assert_equal host_env.fetch("LANG"), child_env.fetch("LANG")
    assert_equal "visible", child_env.fetch("PLYWO_EXPLICIT_SENTINEL")
    refute child_env.key?("RUBYOPT")
    refute child_env.key?("RUBYLIB")
    refute child_env.key?("PLYWO_EXECUTOR_SERVICE_TOKEN")
    refute child_env.key?("PLYWO_GITHUB_WEBHOOK_SECRET")
    refute child_env.key?("SSH_AUTH_SOCK")
  end

  test "caller can explicitly unset an inherited safe variable" do
    runner = Plywo::Github::LocalPullRequestRunner::CommandRunner.new(
      host_env: { "PATH" => ENV.fetch("PATH"), "HOME" => "/private/host-home" }
    )

    output = runner.call(
      env: { "HOME" => nil },
      command: [ RbConfig.ruby, "-e", "print ENV.key?('HOME')" ],
      chdir: Rails.root.to_s
    )

    assert_equal "false", output
  end

  test "subject identity environment overrides caller and host identity values" do
    identity = Struct.new(:environment, :spawn_options).new(
      {
        "HOME" => "/home/plywo-subject",
        "USER" => "plywo-subject",
        "LOGNAME" => "plywo-subject"
      },
      {}
    )
    runner = Plywo::Github::LocalPullRequestRunner::CommandRunner.new(
      host_env: {
        "PATH" => ENV.fetch("PATH"),
        "HOME" => "/root"
      },
      execution_identity: identity
    )

    output = runner.call(
      env: {
        "HOME" => "/attacker-home",
        "USER" => "root",
        "LOGNAME" => "root"
      },
      command: [
        RbConfig.ruby,
        "-e",
        "print [ENV['HOME'], ENV['USER'], ENV['LOGNAME']].join('|')"
      ],
      chdir: Rails.root.to_s
    )

    assert_equal "/home/plywo-subject|plywo-subject|plywo-subject", output
  end

  test "failure diagnostics report environment keys without values" do
    runner = Plywo::Github::LocalPullRequestRunner::CommandRunner.new(
      host_env: { "PATH" => ENV.fetch("PATH"), "HOME" => "/safe/home" }
    )

    error = assert_raises(Plywo::Github::LocalPullRequestRunner::Error) do
      runner.call(
        env: { "PLYWO_SECRET_SENTINEL" => "do-not-print-this-value" },
        command: [ RbConfig.ruby, "-e", "warn 'expected failure'; exit 1" ],
        chdir: Rails.root.to_s
      )
    end

    assert_includes error.message, "expected failure"
    assert_includes error.message, "Effective environment keys:"
    assert_includes error.message, "PLYWO_SECRET_SENTINEL"
    refute_includes error.message, "do-not-print-this-value"
  end
end
