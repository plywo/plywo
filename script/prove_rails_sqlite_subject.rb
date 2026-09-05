#!/usr/bin/env ruby

require "fileutils"
require "open3"
require "pathname"
require "tmpdir"

TOOL_ROOT = Pathname(__dir__).join("..").expand_path.freeze
FIXTURE_ROOT = TOOL_ROOT.join("test", "fixtures", "rails_sqlite_subject").freeze

ENV["RAILS_ENV"] ||= "test"
require TOOL_ROOT.join("config", "environment").to_s

module RailsSqliteSubjectProof
  module_function

  def call
    Dir.mktmpdir("plywo-rails-sqlite-subject-") do |directory|
      subject_root = Pathname(directory)
      prepare_subject_repository(subject_root)
      ensure_subject_bundle(subject_root)

      baseline_sha = commit(subject_root, "Baseline SQLite behavior")
      write_candidate_behavior(subject_root)
      candidate_sha = commit(subject_root, "Increase SQLite query behavior")

      request = build_request(baseline_sha:, candidate_sha:)
      command_runner = Plywo::Github::LocalPullRequestRunner::CommandRunner.new
      environment = Plywo::Subject::RailsSqliteEnvironment.new(command_runner:)
      runner = Plywo::Github::LocalPullRequestRunner.new(
        root: subject_root,
        tool_root: TOOL_ROOT,
        command_runner:,
        fetch_repository: false,
        subject_environment: environment
      )
      result = Plywo::Executor::LocalAdapter.new(runner:).call(request:)

      verify!(result)
      print_proof(request:, result:)
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

  def ensure_subject_bundle(subject_root)
    env = {
      "BUNDLE_GEMFILE" => subject_root.join("Gemfile").to_s,
      "BUNDLE_DEPLOYMENT" => "false",
      "BUNDLE_FROZEN" => "false"
    }
    env["BUNDLE_PATH"] = ENV["BUNDLE_PATH"] if ENV["BUNDLE_PATH"].present?

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
