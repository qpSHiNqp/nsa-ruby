require "eventmachine"
require "./client_handler"

server_addr, server_port = "127.0.0.1", 50000
host, port = "0.0.0.0", 8080

EM.threadpool_size = 100
EM.run do
	Signal.trap("INT") { EM.stop }
	Signal.trap("TERM") { EM.stop }
	srv = EM.connect(server_addr, server_port, NSAClientUpstream)
	EM.start_server(host, port, NSAClientDownstream, srv)
end
