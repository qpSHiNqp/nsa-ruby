require "eventmachine"
require "./server_handler"

host, port = "0.0.0.0", 50000
EM.threadpool_size = 100
EM.run do
	Signal.trap("INT") { EM.stop }
	Signal.trap("TERM") { EM.stop }
	EM.start_server(host, port, NSAServerDownstream)
end
