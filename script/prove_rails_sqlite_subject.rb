#!/usr/bin/env ruby

require "bundler"
require "digest"
require "fileutils"
require "open3"
require "pathname"
require "tmpdir"

TOOL_ROOT = Pathname(__dir__).join("..").expand_path.freeze
FIXTURE_ROOT = TOOL_ROOT.join("test", "fixtures", "rails_sqlite_subject").freeze
TOOL_LOCKFILE = TOOL_ROOT.join("Gemfile.lock").freeze

ENV["RAILS_ENV"] ||= "test"
require TOOL_ROOT.join("config", "environment").to_s

module RailsSqliteSubjectProof
  class GuardedCommandRunner
    def initialize(delegate:, lockfile:, expected_digest:)
      @delegate = delegate
      @lockfile = lockfile
      @expected_digest = expected_digest
    end

    def call(env:, command:, chdir:)
      verify!(phase: "before", command:, chdir:)
      @delegate.call(env:, command:, chdir:)
    ensure
      verify!(phase: "after", command:, chdir:)
    end

    private

    def verify!(phase:, command:, chdir:)
      actual_digest = Digest::SHA256.file(@lockfile).hexdigest
      return if actual_digest == @expected_digest

      raise Plywo::Github::LocalPullRequestRunner::Error,
        "Control-plane lockfile was already mutated #{phase} command: #{command.join(" ")} (chdir=#{chdir})"
    end
  end

  module_function

  def call
    Dir.mktmpdir("plywo-rails-sqlite-subject-") do |directory|
      Dir.mktmpdir("plywo-rails-sqlite-bundle-") do |bundle_directory|
        subject_root = Pathname(directory)
        bundle_root = Pathname(bundle_directory)
        bundle_path = bundle_root.join("gems")
        bundle_app_config = bundle_root.join("config")
        tool_lock_digest = Digest::SHA256.file(TOOL_LOCKFILE).hexdigest

        prepare_subject_repository(subject_root)
        ensure_subject_bundle(subject_root, bundle_path:, bundle_app_config:)
        verify_tool_lock_unchanged!(tool_lock_digest)

        baseline_sha = commit(subject_root, "Baseline SQLite behavior")
        write_candidate_behavior(subject_root)
        candidate_sha = commit(subject_root, "Increase SQLite query behavior")
        verify_tool_lock_unchanged!(tool_lock_digest)

        request = build_request(baseline_sha:, candidate_sha:)
        command_runner = GuardedCommandRunner.new(
          delegate: Plywo::Github::LocalPullRequestRunner::CommandRunner.new,
          lockfile: TOOL_LOCKFILE,
          expected_digest: tool_lock_digest
        )
        environment = Plywo::Subject::RailsSqliteEnvironment.new(
          command_runner:,
          bundle_path:,
          bundle_app_config:
        )
        runner = Plywo::Github::LocalPullRequestRunner.new(
          root: subject_root,
          tool_root: TOOL_ROOT,
          command_runner:,
          fetch_repository: false,
          subject_environment: environment
        )
        result = Plywo::Executor::LocalAdapter.new(runner:).call(request:)

        verify!(result)
        verify_tool_lock_unchanged!(tool_lock_digest)
        print_proof(request:, result:)
      end
    end
  end

  def prepare_subject_repository(subject_root)
    FileUtils.cp_r("#{FIXTURE_ROOT}/.", subject_root)
    FileUtils.mkdir_p(subject_root.join("lib", "plywo"))
    FileUtils.cp(TOOL_ROOT.join("lib", "plywo", "execution_context.rb"), subject_root.join("lib", "plywo"))
    FileUtils.cp_r(TOOL_ROOT.join("lib", "plywo", "rails"), subject_root.join("lib", "plywo", "rails"))

    run!(%w[git init -q], chdir: subject_root)
    run!([ "git", "config", "user.email", "sqlite-proof@plywo.local" ], chdir: subject_root)
    run!([ "git", "config", "user.name", "Plywo SQLite Proof" ], chdir: subject_root)
  end

  def ensure_subject_bundle(subject_root, bundle_path:, bundle_app_config:)
    env = {
      "BUNDLE_GEMFILE" => subject_root.join("Gemfile").to_s,
      "BUNDLE_PATH" => bundle_path.to_s,
      "BUNDLE_APP_CONFIG" => bundle_app_config.to_s,
      "BUNDLE_DEPLOYMENT" => "false",
      "BUNDLE_FROZEN" => "false"
    }

    Bundler.with_unbundled_env do
      return if run(%w[bundle check], chdir: subject_root, env:, allow_failure: true)

      run!(%w[bundle install --jobs 4 --retry 3], chdir: subject_root, env:)
    end
  end

  def commit(subject_root, message)
    run!(%w[git add --all], chdir: subject_root)
    run!([ "git", "commit", "-q", "-m", message ], chdir: subject_root)
    run!(%w[git rev-parse HEAD], chdir: subject_root).strip
  end

  def write_candidate_behavior(subject_root)
    subject_root.join("config", "behavior_profile.rb").write(<<~RUBY)
      module RailsSqliteSubject
        QUERY_COUNT = 8
      end
    RUBY
  end

  def build_request(baseline_sha:, candidate_sha:)
    Plywo::Executor::Request.new(
      schema_version: Plywo::Executor::Request.current_schema_version,
      execution_id: "github-sqlite-proof-001",
      scenario_id: "rails.sqlite.query-behavior",
      baseline_sha:,
      candidate_sha:,
      attempt_number: 1,
      context: {
        "repository" => "fixture/rails-sqlite-subject",
        "candidate_repository" => "fixture/rails-sqlite-subject",
        "pull_request_number" => 1,
        "baseline_ref" => "main",
        "candidate_ref" => "candidate"
      }
    )
  end

  def verify!(result)
    raise "SQLite subject execution failed: #{result.error_class}: #{result.error_message}" unless result.success?

    payload = result.payload
    baseline_queries = payload.dig("executions", "baseline", "measurements", "sql_queries")
    candidate_queries = payload.dig("executions", "candidate", "measurements", "sql_queries")
    finding = payload.dig("result", "findings")&.find do |item|
      item["reason_code"] == "DATABASE_QUERY_REGRESSION"
    end

    raise "SQLite baseline query evidence is missing" unless baseline_queries.is_a?(Numeric)
    raise "SQLite candidate query evidence is missing" unless candidate_queries.is_a?(Numeric)
    raise "Expected candidate SQLite query count to exceed baseline" unless candidate_queries > baseline_queries
    raise "Expected DATABASE_QUERY_REGRESSION from SQLite subject" unless finding
  end

  def verify_tool_lock_unchanged!(expected_digest)
    actual_digest = Digest::SHA256.file(TOOL_LOCKFILE).hexdigest
    return if actual_digest == expected_digest

    raise "SQLite subject dependency setup mutated the Plywo control-plane lockfile"
  end

  def print_proof(request:, result:)
    payload = result.payload
    puts "Rails + SQLite customer subject proof"
    puts "request_schema=#{request.schema_version}"
    puts "result_schema=#{result.schema_version}"
    puts "result_status=#{result.status}"
    puts "baseline_sql_queries=#{payload.dig("executions", "baseline", "measurements", "sql_queries")}"
    puts "candidate_sql_queries=#{payload.dig("executions", "candidate", "measurements", "sql_queries")}"
    puts "reason_code=DATABASE_QUERY_REGRESSION"
    puts "merge_recommendation=#{payload.dig("result", "merge_recommendation")}"
    puts "control_plane_lockfile_unchanged=true"
  end

  def run!(command, chdir:, env: {})
    stdout, stderr, status = Open3.capture3(env, *command, chdir: chdir.to_s)
    return stdout if status.success?

    raise "Command failed (#{command.join(" ")}): #{stderr.presence || stdout}"
  end

  def run(command, chdir:, env: {}, allow_failure: false)
    run!(command, chdir:, env:)
    true
  rescue StandardError
    raise unless allow_failure

    false
  end
end

RailsSqliteSubjectProof.call
