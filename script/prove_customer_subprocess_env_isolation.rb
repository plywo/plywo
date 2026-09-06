#!/usr/bin/env ruby

ENV["RAILS_ENV"] ||= "production"
require_relative "../config/environment"
require "json"
require "rbconfig"

secret = ENV.fetch("PLYWO_CUSTOMER_SECRET_SENTINEL")
runner = Plywo::Github::LocalPullRequestRunner::CommandRunner.new
keys = %w[
  PLYWO_CUSTOMER_SECRET_SENTINEL
  PLYWO_EXECUTOR_SERVICE_TOKEN
  RUBYOPT
  RUBYLIB
  PLYWO_EXPLICIT_SENTINEL
]
script = "require 'json'; print JSON.generate(ENV.to_h.slice(*#{keys.inspect}))"

output = runner.call(
  env: { "PLYWO_EXPLICIT_SENTINEL" => "visible" },
  command: [ RbConfig.ruby, "-e", script ],
  chdir: Rails.root.to_s
)
child_env = JSON.parse(output)

raise "Customer subprocess inherited the proof secret" if child_env["PLYWO_CUSTOMER_SECRET_SENTINEL"] == secret
raise "Customer subprocess inherited executor service credentials" if child_env.key?("PLYWO_EXECUTOR_SERVICE_TOKEN")
raise "Customer subprocess inherited RUBYOPT" if child_env.key?("RUBYOPT")
raise "Customer subprocess inherited RUBYLIB" if child_env.key?("RUBYLIB")
raise "Explicit customer environment was lost" unless child_env["PLYWO_EXPLICIT_SENTINEL"] == "visible"

puts "customer_subprocess_env_isolated=true"
puts "executor_service_token_inherited=false"
puts "ruby_load_environment_inherited=false"
