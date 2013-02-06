require "socket"
require "./nsa_utils"

class NSAClientUpstream < EM::Connection
	include NSAUtils

	def initialize
		@downstreams = Hash.new
	end # initialize

	def send_data(data, id, flag="\x00")
		super pack_header(data, id, flag)
	end # send_data (override)

	def receive_data(data)
		id, flag, data = unpack_header(data)
		
		@downstreams[id].send_data(data) unless @downstreams[id].nil? || data.bytesize == 0
		@downstreams[id].handle_shutdown_signal if flag == "\x10" && !@downstreams[id].nil?
	end # receive_data

	def unbind
		# TODO attempt to reconnect
	end # unbind

	def add_downstream(d, id)
		@downstreams[id] = d
	end # add_downstreams

	def remove_downstream(id)
		@downstreams.delete(id)
	end # remove_downstream

	def issue_shutdown_signal(id)
		send_data("", id, "\x10")
	end # issue_shutdown_signal
end # NSAClientUpstream

class NSAClientDownstream < EM::Connection
	def initialize(upstream)
		@upstream = upstream
		@state = nil
		@active_close = false
	end # initialize

	def post_init
		@id, _ = Socket.unpack_sockaddr_in(get_peername)
		@state = :connected
		@upstream.add_downstream(self, @id)
	end # post_init

	def receive_data(data)
		@upstream.send_data(data, @id)
	end # receive_data

	def unbind
		@upstream.issue_shutdown_signal(@id) unless @active_close
		@state = :closed
		@upstream.remove_downstream(@id)
	end # unbind

	def handle_shutdown_signal
		@active_close = true
		close_connection_after_writing unless @state == :closed
	end # handle_shutdown_signal
end # NSAClientDownstream
