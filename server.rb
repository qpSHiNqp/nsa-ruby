require 'eventmachine'
require './handler.rb'

host,port = "0.0.0.0", 8080
puts "Starting server on #{host}:#{port}, #{EM::set_descriptor_table_size(32768)} sockets"
EM.run do
	EM.start_server host, port, RequestHandler
	if ARGV.size > 0
		forks = ARGV[0].to_i
		puts "... forking #{forks} times => #{2**forks} instances"
		forks.times { fork }
	end
end
