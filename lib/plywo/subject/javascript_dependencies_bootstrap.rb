require "digest"
require "pathname"

module Plywo
  module Subject
    class JavascriptDependenciesBootstrap
      Error = Class.new(StandardError)

      def initialize(command_runner:)
        @command_runner = command_runner
      end

      def call(root:, step:)
        root = Pathname(root).expand_path
        manifest = root.join(step.details.fetch("manifest"))
        lockfile = root.join(step.details.fetch("lockfile"))

        raise Error, "JavaScript subject is missing package.json at #{manifest}" unless manifest.file?
        raise Error, "JavaScript subject is missing committed lockfile at #{lockfile}" unless lockfile.file?

        original_manifest_digest = Digest::SHA256.file(manifest).hexdigest
        original_lockfile_digest = Digest::SHA256.file(lockfile).hexdigest

        run!(command_for(step), chdir: root)

        assert_unchanged!(manifest, original_manifest_digest, label: "package.json")
        assert_unchanged!(lockfile, original_lockfile_digest, label: step.details.fetch("lockfile"))
        {}
      end

      private

      def command_for(step)
        manager = step.details.fetch("manager")

        case manager
        when "npm"
          %w[npm ci]
        when "pnpm"
          %w[pnpm install --frozen-lockfile]
        when "yarn"
          yarn_command(step)
        when "bun"
          %w[bun install --frozen-lockfile]
        else
          raise Error, "Unsupported JavaScript package manager #{manager.inspect}"
        end
      end

      def yarn_command(step)
        case step.details.fetch("yarn_generation", nil)
        when "classic"
          %w[yarn install --frozen-lockfile]
        when "berry"
          %w[yarn install --immutable]
        else
          raise Error, "Yarn dependency bootstrap requires deterministic yarn_generation evidence"
        end
      end

      def run!(command, chdir:)
        @command_runner.call(env: {}, command:, chdir: chdir.to_s)
      end

      def assert_unchanged!(path, expected_digest, label:)
        unless path.file?
          raise Error, "JavaScript dependency bootstrap removed committed #{label}"
        end

        actual_digest = Digest::SHA256.file(path).hexdigest
        return if actual_digest == expected_digest

        raise Error, "JavaScript dependency bootstrap mutated committed #{label}"
      end
    end
  end
end
