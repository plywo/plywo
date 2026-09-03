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

    abort "Plywo detected a behavioral regression" if ENV["FAIL_ON_REGRESSION"] == "1" && result.fetch("decision") == "regression"
  end
end
