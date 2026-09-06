require "test_helper"
require "tmpdir"

class PlywoSubjectConfigurationTest < ActiveSupport::TestCase
  test "missing config keeps automatic persistence and current scenario default" do
    Dir.mktmpdir do |directory|
      configuration = Plywo::Subject::Configuration.load(root: directory)

      assert_equal "auto", configuration.persistence
      assert_nil configuration.scenario_path
      assert_equal({}, configuration.capture_env)
      assert_nil configuration.source_path
    end
  end

  test "loads candidate scenario and persistence override" do
    Dir.mktmpdir do |directory|
      File.write(File.join(directory, "plywo.yml"), <<~YAML)
        version: 1
        scenario:
          path: /orders/42
        subject:
          persistence: sqlite
      YAML

      configuration = Plywo::Subject::Configuration.load(root: directory)

      assert_equal "sqlite", configuration.persistence
      assert_equal "/orders/42", configuration.scenario_path
      assert_equal({ "PLYWO_SCENARIO_PATH" => "/orders/42" }, configuration.capture_env)
      assert_equal Pathname(directory).join("plywo.yml"), configuration.source_path
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
