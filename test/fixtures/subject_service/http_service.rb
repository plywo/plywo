require "socket"

server = TCPServer.new("127.0.0.1", Integer(ARGV.fetch(0)))

trap("TERM") do
  server.close
  exit
end

loop do
  client = server.accept
  request_line = client.gets
  next client.close unless request_line

  while (line = client.gets)
    break if line == "\r\n"
  end

  path = request_line.split.fetch(1)
  body = path == "/health" ? "ok" : "service-ready"

  client.write(
    "HTTP/1.1 200 OK\r\n" \
    "Content-Type: text/plain\r\n" \
    "Content-Length: #{body.bytesize}\r\n" \
    "Connection: close\r\n" \
    "\r\n" \
    "#{body}"
  )
  client.close
end
