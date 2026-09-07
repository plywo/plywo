require "test_helper"

class PlywoGithubAppAuthenticationEnvironmentTest < ActiveSupport::TestCase
  test "from_env honors the GitHub API base URL" do
    previous = {
      "PLYWO_GITHUB_PRIVATE_KEY_PATH" => ENV["PLYWO_GITHUB_PRIVATE_KEY_PATH"],
      "PLYWO_GITHUB_APP_ID" => ENV["PLYWO_GITHUB_APP_ID"],
      "GITHUB_API_URL" => ENV["GITHUB_API_URL"]
    }
    ENV["PLYWO_GITHUB_PRIVATE_KEY_PATH"] = "tmp/lab-app.pem"
    ENV["PLYWO_GITHUB_APP_ID"] = "12345"
    ENV["GITHUB_API_URL"] = "http://github-emulator:4001"
    captured = nil
    authentication = Object.new

    factory = lambda do |**attributes|
      captured = attributes
      authentication
    end

    result = Plywo::Github::AppAuthentication.stub(:new, factory) do
      Plywo::Github::AppAuthentication.from_env(root: "/srv/plywo")
    end

    assert_same authentication, result
    assert_equal "12345", captured.fetch(:app_id)
    assert_equal "/srv/plywo/tmp/lab-app.pem", captured.fetch(:private_key_path)
    assert_equal "http://github-emulator:4001", captured.fetch(:api_url)
  ensure
    previous&.each do |name, value|
      value.nil? ? ENV.delete(name) : ENV[name] = value
    end
  end
end
