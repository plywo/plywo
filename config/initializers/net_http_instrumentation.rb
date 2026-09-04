require "net/http"

Net::HTTP.prepend(Plywo::Rails::NetHttpInstrumentation) unless Net::HTTP < Plywo::Rails::NetHttpInstrumentation
