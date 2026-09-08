require "json"
require "pathname"

module Plywo
  module Subject
    class JavascriptPackageManagerDetector
      Error = Class.new(StandardError)

      SUPPORTED_LOCKFILES = {
        "package-lock.json" => "npm",
        "pnpm-lock.yaml" => "pnpm",
        "yarn.lock" => "yarn",
        "bun.lock" => "bun",
        "bun.lockb" => "bun"
      }.freeze
      SUPPORTED_MANAGERS = SUPPORTED_LOCKFILES.values.uniq.freeze

      Detection = Data.define(:manager, :manifest, :lockfile, :package_manager_declaration) do
        def bootstrap_step
          SetupPlan::Step.new(
            phase: "bootstrap",
            operation: "javascript.dependencies",
            provenance: "detected",
            details: {
              manager:,
              manifest:,
              lockfile:,
              frozen_lockfile: true
            }
          )
        end

        def evidence
          {
            "package_json" => true,
            "javascript_package_manager" => manager,
            "javascript_lockfile" => lockfile,
            "package_manager_declaration" => package_manager_declaration
          }.compact
        end
      end

      def call(root:)
        root = Pathname(root)
        manifest = root.join("package.json")
        return unless manifest.file?

        payload = parse_manifest!(manifest)
        lockfile = detect_lockfile!(root)
        manager = SUPPORTED_LOCKFILES.fetch(lockfile)
        declaration = payload["packageManager"]
        assert_declaration_matches!(declaration:, manager:, lockfile:)

        Detection.new(
          manager:,
          manifest: "package.json",
          lockfile:,
          package_manager_declaration: declaration
        )
      end

      private

      def parse_manifest!(manifest)
        payload = JSON.parse(manifest.read)
        return payload if payload.is_a?(Hash)

        raise Error, "package.json must contain a JSON object"
      rescue JSON::ParserError => error
        raise Error, "Invalid package.json: #{error.message}"
      end

      def detect_lockfile!(root)
        lockfiles = SUPPORTED_LOCKFILES.keys.select { |name| root.join(name).file? }

        if lockfiles.empty?
          supported = SUPPORTED_LOCKFILES.keys.sort.join(", ")
          raise Error,
            "JavaScript package.json requires exactly one supported committed lockfile; " \
            "found none (supported: #{supported})"
        end

        if lockfiles.length > 1
          raise Error,
            "Ambiguous JavaScript package manager: multiple supported lockfiles found: " \
            "#{lockfiles.sort.join(", ")}"
        end

        lockfiles.sole
      end

      def assert_declaration_matches!(declaration:, manager:, lockfile:)
        return if declaration.nil?

        declared_manager = declaration.to_s.split("@", 2).first
        unless SUPPORTED_MANAGERS.include?(declared_manager)
          raise Error, "Unsupported package.json packageManager #{declaration.inspect}"
        end
        return if declared_manager == manager

        raise Error,
          "package.json packageManager declares #{declared_manager} but #{lockfile} selects #{manager}"
      end
    end
  end
end
