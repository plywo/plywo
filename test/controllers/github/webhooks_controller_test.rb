require "test_helper"

class GithubWebhooksControllerTest < ActionDispatch::IntegrationTest
  test "accepts a correctly signed webhook" do
    previous_secret = ENV["PLYWO_GITHUB_WEBHOOK_SECRET"]
    ENV["PLYWO_GITHUB_WEBHOOK_SECRET"] = "development-secret"
    payload = JSON.generate(
      "action" => "created",
      "installation" => { "id" => 123 }
    )
    signature = "sha256=#{OpenSSL::HMAC.hexdigest("SHA256", ENV.fetch("PLYWO_GITHUB_WEBHOOK_SECRET"), payload)}"

    post github_webhooks_url,
      params: payload,
      headers: {
        "CONTENT_TYPE" => "application/json",
        "X-Hub-Signature-256" => signature,
        "X-GitHub-Event" => "installation",
        "X-GitHub-Delivery" => "delivery-1"
      }

    assert_response :accepted
    body = response.parsed_body
    assert_equal true, body.fetch("ok")
    assert_equal "installation", body.fetch("event")
    assert_equal 123, body.fetch("installation_id")
  ensure
    ENV["PLYWO_GITHUB_WEBHOOK_SECRET"] = previous_secret
  end

  test "rejects an unsigned webhook" do
    previous_secret = ENV["PLYWO_GITHUB_WEBHOOK_SECRET"]
    ENV["PLYWO_GITHUB_WEBHOOK_SECRET"] = "development-secret"

    post github_webhooks_url,
      params: "{}",
      headers: {
        "CONTENT_TYPE" => "application/json",
        "X-GitHub-Event" => "ping"
      }

    assert_response :unauthorized
  ensure
    ENV["PLYWO_GITHUB_WEBHOOK_SECRET"] = previous_secret
  end
end
