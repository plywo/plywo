require "test_helper"

class PlywoGithubAppManifestTest < ActiveSupport::TestCase
  test "resolves the development manifest against the public URL" do
    manifest = Plywo::Github::AppManifest.new(
      environment: "development",
      public_url: "https://plywo-dev.example.test/"
    ).to_h

    assert_equal "Plywo Development", manifest.fetch("name")
    assert_equal "https://plywo-dev.example.test/github/webhooks", manifest.dig("hook_attributes", "url")
    assert_equal "https://plywo-dev.example.test/github/app/manifest/callback", manifest.fetch("redirect_url")
    assert_equal "write", manifest.dig("default_permissions", "checks")
    assert_equal "read", manifest.dig("default_permissions", "contents")
    assert_equal "write", manifest.dig("default_permissions", "pull_requests")
  end

  test "resolves the staging manifest" do
    manifest = Plywo::Github::AppManifest.new(
      environment: "staging",
      public_url: "https://plywo-staging.example.test"
    ).to_h

    assert_equal "Plywo Staging", manifest.fetch("name")
    assert_equal "https://plywo-staging.example.test/github/webhooks", manifest.dig("hook_attributes", "url")
    assert_equal "https://plywo-staging.example.test/github/app/manifest/callback", manifest.fetch("redirect_url")
  end

  test "resolves the production manifest" do
    manifest = Plywo::Github::AppManifest.new(
      environment: "production",
      public_url: "https://plywo.example.test"
    ).to_h

    assert_equal "Plywo", manifest.fetch("name")
    assert_equal "https://plywo.example.test/github/webhooks", manifest.dig("hook_attributes", "url")
  end

  test "rejects a non HTTPS public URL" do
    error = assert_raises(ArgumentError) do
      Plywo::Github::AppManifest.new(
        environment: "development",
        public_url: "http://localhost:3000"
      )
    end

    assert_match(/HTTPS origin/, error.message)
  end
end
