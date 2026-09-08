#!/usr/bin/env ruby
# frozen_string_literal: true

socket_path = ENV.fetch("PLYWO_COMPOSE_PROVIDER_SOCKET")

require_relative "../lib/plywo/subject/isolated_compose_provider_server"

server = Plywo::Subject::IsolatedComposeProviderServer.new(socket_path:)
%w[TERM INT].each do |signal|
  Signal.trap(signal) do
    server.shutdown
    exit! 0
  end
end

server.run
