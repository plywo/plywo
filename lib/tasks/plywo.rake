namespace :plywo do
  desc "Run Plywo against its own Rails demo execution"
  task dogfood: :environment do
    payload = Plywo::Demo::DogfoodRunner.call
    result = payload.fetch("result")

    puts "Plywo dogfood run: #{payload.fetch("run_id")}"
    puts "Scenario: #{payload.fetch("scenario_id")}"
    puts
    puts Plywo::ReportRenderer.markdown(result)
    puts
    puts JSON.pretty_generate(payload) if ENV["PLYWO_JSON"] == "1"
    File.write(ENV.fetch("PLYWO_OUTPUT"), JSON.pretty_generate(payload)) if ENV["PLYWO_OUTPUT"]

    abort "Plywo detected a behavioral regression" if ENV["FAIL_ON_REGRESSION"] == "1" && result.fetch("decision") == "regression"
  end

  desc "Compose two captured executions into one behavioral comparison payload"
  task compare_executions: :environment do
    baseline = JSON.parse(File.read(ENV.fetch("PLYWO_BASELINE_INPUT")))
    candidate = JSON.parse(File.read(ENV.fetch("PLYWO_CANDIDATE_INPUT")))
    payload = Plywo::ExecutionPair.call(baseline:, candidate:)

    puts Plywo::ReportRenderer.markdown(payload.fetch("result"))
    puts
    puts JSON.pretty_generate(payload)
    File.write(ENV.fetch("PLYWO_OUTPUT"), JSON.pretty_generate(payload)) if ENV["PLYWO_OUTPUT"]
  end

  desc "Render and optionally publish the durable Plywo GitHub PR comment"
  task github_comment: :environment do
    payload = JSON.parse(File.read(ENV.fetch("PLYWO_INPUT")))
    event = if ENV["GITHUB_EVENT_PATH"] && File.exist?(ENV["GITHUB_EVENT_PATH"])
      JSON.parse(File.read(ENV["GITHUB_EVENT_PATH"]))
    else
      {}
    end

    pr_number = ENV["PLYWO_PR_NUMBER"] || event["number"] || event.dig("pull_request", "number")
    context = {
      repository: ENV["GITHUB_REPOSITORY"],
      pr_number:,
      baseline_label: ENV["PLYWO_BASELINE_LABEL"] || event.dig("pull_request", "base", "ref"),
      baseline_sha: ENV["PLYWO_BASELINE_SHA"] || event.dig("pull_request", "base", "sha"),
      candidate_label: ENV["PLYWO_CANDIDATE_LABEL"] || event.dig("pull_request", "head", "ref"),
      candidate_sha: ENV["PLYWO_CANDIDATE_SHA"] || event.dig("pull_request", "head", "sha"),
      bootstrap_baseline: ENV["PLYWO_BOOTSTRAP_BASELINE"],
      execution_mode: ENV["PLYWO_EXECUTION_MODE"],
      run_url: ENV["PLYWO_RUN_URL"]
    }
    markdown = Plywo::Github::CommentRenderer.markdown(payload:, context:)

    puts markdown
    File.write(ENV.fetch("PLYWO_COMMENT_OUTPUT"), markdown) if ENV["PLYWO_COMMENT_OUTPUT"]

    next unless ENV["PLYWO_PUBLISH"] == "1"

    publisher = Plywo::Github::CommentPublisher.new(
      token: ENV.fetch("GITHUB_TOKEN"),
      api_url: ENV.fetch("GITHUB_API_URL", "https://api.github.com")
    )
    action = publisher.upsert(
      repository: ENV.fetch("GITHUB_REPOSITORY"),
      pr_number: Integer(pr_number),
      body: markdown,
      author: ENV["PLYWO_COMMENT_AUTHOR"]
    )
    puts "Plywo GitHub comment #{action}."
  end
end
