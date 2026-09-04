require "test_helper"
require "tmpdir"

class PlywoGithubDevelopmentCredentialStoreTest < ActiveSupport::TestCase
  test "stores ignored development credentials and updates the current process" do
    Dir.mktmpdir do |directory|
      root = Pathname(directory)
      credentials = {
        "id" => 123,
        "client_id" => "Iv1.client",
        "webhook_secret" => "secret",
        "pem" => "-----BEGIN PRIVATE KEY-----\ntest\n-----END PRIVATE KEY-----\n"
      }
      previous = %w[
        PLYWO_GITHUB_APP_ID
        PLYWO_GITHUB_CLIENT_ID
        PLYWO_GITHUB_WEBHOOK_SECRET
        PLYWO_GITHUB_PRIVATE_KEY_PATH
      ].to_h { |key| [ key, ENV[key] ] }

      store = Plywo::Github::DevelopmentCredentialStore.new(root:).write!(credentials)

      assert_equal credentials.fetch("pem"), store.private_key_path.read
      assert_includes store.env_path.read, "export PLYWO_GITHUB_APP_ID=123"
      assert_equal "secret", ENV.fetch("PLYWO_GITHUB_WEBHOOK_SECRET")
      assert_equal "tmp/github-app/plywo-development.pem", ENV.fetch("PLYWO_GITHUB_PRIVATE_KEY_PATH")
      assert_equal 0o600, store.private_key_path.stat.mode & 0o777
      assert_equal 0o600, store.env_path.stat.mode & 0o777
    ensure
      previous.each { |key, value| ENV[key] = value }
    end
  end
end
