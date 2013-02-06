require 'eventmachine'
require './server_handler.rb'

host,port = "0.0.0.0", 50000
puts "Starting server on #{host}:#{port}, #{EM::set_descriptor_table_size(32768)} sockets"
EM.threadpool_size = 100
EM.run do
	Signal.trap("INT") { EM.stop }
	Signal.trap("TERM") { EM.stop }
	EM.start_server host, port, NSAServer
	if ARGV.size > 0
		forks = ARGV[0].to_i
		puts "... forking #{forks} times => #{2**forks} instances"
		forks.times { fork }
	end
end
