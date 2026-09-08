#!/usr/bin/env ruby

require "open3"
require "pathname"

TOOL_ROOT = Pathname(__dir__).join("..").expand_path.freeze
require TOOL_ROOT.join("lib", "plywo", "subject", "runtime_capabilities").to_s

capabilities = Plywo::Subject::RuntimeCapabilities.from_env
if capabilities.service_provider?("compose")
  raise "Production executor must not declare Compose until it has an isolated service-provider boundary"
end

_stdout, _stderr, status = Open3.capture3("sh", "-c", "command -v docker")
raise "Production executor image must not expose Docker CLI to customer-code processes" if status.success?

puts "Production Compose isolation proof"
puts "compose_service_provider_declared=false"
puts "docker_cli_present=false"
puts "docker_socket_required=false"
