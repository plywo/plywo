require "test_helper"
require "tmpdir"

class PlywoSubjectConfigurationTest < ActiveSupport::TestCase
  test "missing config keeps automatic persistence and setup defaults" do
    Dir.mktmpdir do |directory|
      configuration = Plywo::Subject::Configuration.load(root: directory)

      assert_equal "auto", configuration.persistence
      assert_equal "auto", configuration.setup_mode
      assert_empty configuration.services
      assert_nil configuration.scenario_path
      assert_equal({}, configuration.capture_env)
      assert_nil configuration.source_path
    end
  end

  test "loads candidate scenario, persistence, and setup mode" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "plywo.yml"), <<~YAML)
        version: 1
        scenario:
          path: /orders/42
        subject:
          persistence: sqlite
          setup:
            mode: auto
      YAML

      configuration = Plywo::Subject::Configuration.load(root: directory)

      assert_equal "sqlite", configuration.persistence
      assert_equal "auto", configuration.setup_mode
      assert_empty configuration.services
      assert_equal "/orders/42", configuration.scenario_path
      assert_equal({ "PLYWO_SCENARIO_PATH" => "/orders/42" }, configuration.capture_env)
      assert_equal Pathname(directory).join("plywo.yml"), configuration.source_path
    end
  end

  test "loads explicit process service with bounded HTTP readiness" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "plywo.yml"), <<~YAML)
        version: 1
        subject:
          services:
            - name: mock-api
              type: process
              command: [ruby, script/mock_api.rb]
              port_env: MOCK_API_PORT
              url_env: MOCK_API_URL
              readiness:
                type: http
                path: /health
                timeout_seconds: 3
      YAML

      configuration = Plywo::Subject::Configuration.load(root: directory)
      service = configuration.services.fetch(0)

      assert_equal "mock-api", service.name
      assert_equal "process", service.type
      assert_equal [ "ruby", "script/mock_api.rb" ], service.command
      assert_equal "MOCK_API_PORT", service.port_env
      assert_equal "MOCK_API_URL", service.url_env
      assert_equal "http", service.readiness.type
      assert_equal "/health", service.readiness.path
      assert_equal 3, service.readiness.timeout_seconds
    end
  end

  test "rejects unknown versions and persistence values" do
    Dir.mktmpdir do |directory|
      path = File.join(directory, "plywo.yml")
      File.write(path, "version: 2\n")

      error = assert_raises(Plywo::Subject::Configuration::Error) do
        Plywo::Subject::Configuration.load(root: directory)
      end
      assert_match(/Unsupported plywo.yml version/, error.message)

      File.write(path, "version: 1\nsubject:\n  persistence: mysql\n")
      error = assert_raises(Plywo::Subject::Configuration::Error) do
        Plywo::Subject::Configuration.load(root: directory)
      end
      assert_match(/Unsupported subject.persistence/, error.message)
    end
  end

  test "rejects unsupported setup modes" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "plywo.yml"), <<~YAML)
        version: 1
        subject:
          setup:
            mode: shell
      YAML

      error = assert_raises(Plywo::Subject::Configuration::Error) do
        Plywo::Subject::Configuration.load(root: directory)
      end

      assert_match(/Unsupported subject.setup.mode/, error.message)
    end
  end

  test "rejects shell-string service commands" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "plywo.yml"), <<~YAML)
        version: 1
        subject:
          services:
            - name: mock-api
              type: process
              command: ruby script/mock_api.rb
              url_env: MOCK_API_URL
              readiness:
                type: http
                path: /health
      YAML

      error = assert_raises(Plywo::Subject::Configuration::Error) do
        Plywo::Subject::Configuration.load(root: directory)
      end

      assert_match(/command must be a non-empty sequence/, error.message)
    end
  end

  test "rejects duplicate service names" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "plywo.yml"), <<~YAML)
        version: 1
        subject:
          services:
            - name: mock-api
              type: process
              command: [ruby, one.rb]
              url_env: MOCK_API_URL
              readiness:
                type: http
                path: /health
            - name: mock-api
              type: process
              command: [ruby, two.rb]
              url_env: OTHER_API_URL
              readiness:
                type: http
                path: /health
      YAML

      error = assert_raises(Plywo::Subject::Configuration::Error) do
        Plywo::Subject::Configuration.load(root: directory)
      end

      assert_match(/Duplicate subject.services names: mock-api/, error.message)
    end
  end

  test "rejects unsafe or malformed scenario paths" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "plywo.yml"), "version: 1\nscenario:\n  path: orders/42\n")

      error = assert_raises(Plywo::Subject::Configuration::Error) do
        Plywo::Subject::Configuration.load(root: directory)
      end

      assert_match(/scenario.path must be an absolute HTTP path/, error.message)
    end
  end
end
