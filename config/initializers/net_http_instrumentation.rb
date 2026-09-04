require "net/http"
require Rails.root.join("lib/plywo/rails/net_http_instrumentation").to_s

Net::HTTP.prepend(Plywo::Rails::NetHttpInstrumentation) unless Net::HTTP < Plywo::Rails::NetHttpInstrumentation
