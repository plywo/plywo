require "test_helper"
require "tmpdir"

class PlywoSubjectRailsSqliteEnvironmentTest < ActiveSupport::TestCase
  Execution = Data.define(:execution_id)

  class CommandRecorder
    attr_reader :calls

    def initialize
      @calls = []
    end

    def call(env:, command:, chdir:)
      @calls << { env:, command:, chdir: }
      ""
    end
  end

  test "prepares an isolated Rails SQLite subject environment" do
    Dir.mktmpdir do |directory|
      command_runner = CommandRecorder.new
      environment = Plywo::Subject::RailsSqliteEnvironment.new(
        command_runner:,
        state_root: directory
      )
      execution = Execution.new("github-abcdef1234567890")
      root = Pathname("/tmp/customer-subject")

      env = environment.prepare(root:, execution:, role: "base")

      assert_equal File.join(directory, "plywo_subject_abcdef123456_base.sqlite3"), env.fetch("PLYWO_SQLITE_DATABASE")
      assert_equal root.join("Gemfile").to_s, env.fetch("BUNDLE_GEMFILE")
      assert_equal "test", env.fetch("RAILS_ENV")
      assert_equal "test_adapter", env.fetch("PLYWO_ASYNC_TRANSPORT")
      assert_not env.key?("DATABASE_URL")
      assert_not env.key?("SOLID_QUEUE_DATABASE_URL")

      call = command_runner.calls.fetch(0)
      assert_equal env, call.fetch(:env)
      assert_equal [ root.join("bin", "rails").to_s, "db:prepare" ], call.fetch(:command)
      assert_equal root.to_s, call.fetch(:chdir)
    end
  end

  test "uses distinct SQLite files for baseline and candidate and cleans sidecars" do
    Dir.mktmpdir do |directory|
      environment = Plywo::Subject::RailsSqliteEnvironment.new(
        command_runner: CommandRecorder.new,
        state_root: directory
      )
      execution = Execution.new("github-abcdef1234567890")
      root = Pathname("/tmp/customer-subject")

      baseline = environment.env_for(root:, execution:, role: "base").fetch("PLYWO_SQLITE_DATABASE")
      candidate = environment.env_for(root:, execution:, role: "candidate").fetch("PLYWO_SQLITE_DATABASE")

      assert_not_equal baseline, candidate
      assert_match(/_base\.sqlite3\z/, baseline)
      assert_match(/_candidate\.sqlite3\z/, candidate)

      [ baseline, "#{baseline}-wal", "#{baseline}-shm" ].each { |path| File.write(path, "stale") }
      environment.cleanup(root:, execution:, role: "base")

      assert_not File.exist?(baseline)
      assert_not File.exist?("#{baseline}-wal")
      assert_not File.exist?("#{baseline}-shm")
    end
  end
end
