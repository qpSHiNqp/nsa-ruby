require 'socket'
require './nsa_utils'

class NSAClient < EM::Connection
	include NSAUtils

	def initialize
		@request_handlers = Hash.new
	end

	def send_data_with_id(data, id, flag = "\x00")
		packed_data = pack_header(data, id, flag)
		send_data(packed_data)
	end

	def receive_data(packed_data)
		id, flag, data = unpack_header(packed_data)

		# send back response to client
		@request_handlers[id].send_data(data) unless @request_handlers[id].nil? || data.bytesize == 0

		@request_handlers[id].handle_shutdown_signal if flag == "\x10" && !@request_handlers[id].nil?
	end

	def unbind
		p "unbind from server"
		# TODO attempt to reconnect
	end

	def add_request_handler(rh, id)
		p "added session: #{id}"
		@request_handlers[id] = rh
	end

	def remove_request_handler(id)
		@request_handlers.delete(id)
	end

	def issue_shutdown_signal(id)
		send_data_with_id("", id, "\x10")
	end
end

class RequestHandler < EM::Connection
	def initialize(upstream)
		@upstream = upstream
		@state = :not_connected
	end

	def send_data(data)
		p "response data: #{data.bytesize}, id: #{@id}"
		super
	end

	def post_init
		@id, _ = Socket.unpack_sockaddr_in(get_peername)
		@state = :connected
		p "connection established; port: #{@id}"
		@upstream.add_request_handler(self, @id)
	end

	def receive_data(data)
		@upstream.send_data_with_id(data, @id)
	end

	def unbind
		@upstream.issue_shutdown_signal(@id) unless @active_close || @upstream.nil?
		@state = :closed
		@upstream.remove_request_handler(@id)
	end

	def handle_shutdown_signal
		@active_close = true
		close_connection_after_writing unless @state == :closed
	end
end
