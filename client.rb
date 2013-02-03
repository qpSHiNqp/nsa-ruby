require 'eventmachine'
require './client_handler.rb'

server_addr, server_port = "127.0.0.1", 50000
host,port = "0.0.0.0", 8080
puts "Starting server on #{host}:#{port}, #{EM::set_descriptor_table_size(32768)} sockets"
EM.run do
	Signal.trap("INT") { EM.stop }
	Signal.trap("TERM") { EM.stop }
	nsa_client = EM.connect(server_addr, server_port, NSAClient)
	EM.start_server host, port, RequestHandler, nsa_client
	if ARGV.size > 0
		forks = ARGV[0].to_i
		puts "... forking #{forks} times => #{2**forks} instances"
		forks.times { fork }
	end
end
