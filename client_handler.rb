require 'socket'

class NSAClient < EM::Connection
	def initialize
		@request_handlers = Hash.new
	end

	def send_data(data, id, flag = "\x00")
		p data
		data = pack_header(data, id)
		super data
	end

	def receive_data(data)
		id, flag, data = unpack_header(data)

		# send back response to client
		@request_handlers[id].send_data(data)

		@request_handlers[id].handle_shutdown_signal if flag == "\x10"
	end

	def unbind
		p "unbind from server"
		# TODO attempt to reconnect
	end

	def add_request_handler(rh, id)
		@request_handlers[id] = rh
	end

	def remove_request_handler(id)
		@request_handlers.delete(id)
	end

	def issue_shutdown_signal(id)
		send_data("", id, "\x10")
	end
end

class RequestHandler < EM::Connection
	def initialize(upstream)
		@upstream = upstream
		@host = @port = nil
		@state = :not_connected
	end

	def receive_data(data)
		@upstream.send_data(data, @id)
	end

	def connection_completed
		peeraddr = Socket.unpack_sockaddr_in(get_peername)
		@id = peeraddr[1]
		@state = :connected
		p "connection established to browser: #{peeraddr}"
		@upstream.add_request_handler(self, @id)
	end

	def unbind
		p "unbind from browser"
		issue_shutdown_signal
		@state = :closed
		@upstream.remove_request_handler(@id)
	end

	def issue_shutdown_signal
		@upstream.issue_shutdown_signal(@id) unless @active_close || @upstream.nil?
	end

	def handle_shutdown_signal
		@active_close = true
		close_connection_after_writing unless @state == :closed
	end
end
