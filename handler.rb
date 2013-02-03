require 'uri'
require 'socket'

HTTP_1_0                 = 'HTTP/1.0'.freeze
CONNECTION_REGEXP        = /^Connection:\s*([\S]+)/i.freeze
PROXY_CONNECTION_REGEXP  = /^Proxy-Connection:\s([\S]+)$/i.freeze
KEEP_ALIVE_REGEXP        = /\bkeep-alive\b/i.freeze
CLOSE_REGEXP             = /\bclose\b/i.freeze
CONTENT_LENGTH_REGEXP    = /^Content-Length:\s+(\d+)/i.freeze
TRANSFER_ENCODING_REGEXP = /^Transfer-Encoding:\s*(\w+)/i.freeze

#$debug = true.freeze
#$downstream_count = 0
#$upstream_count = 0
#$upstream_conn = Hash.new
#$m = Mutex.new

class Upstream < EM::Connection
	attr_reader :mode

	def initialize(rh)
		@request_handler = rh
		@mode = :proxy
		@state = :not_connected
	end

	def post_init
		@state = :connected
	end

	def create_tunnel(data)
		@mode = :tunnel
		response = "HTTP/1.1 200 connection established\r\n\r\n"
		@request_handler.send_data(response)
	end

	def send_data(data)
		p data
		super data
	end

	def receive_data(data)
		if @mode == :tunnel then
			@request_handler.send_data(data)
			return
		end

		if data.byteslice(0,10) =~ /HTTP\/1.\d\s/i then
			# keep-alive or not
			header, body = data.split(/\r?\n\r?\n/, 2)
			http_version, _ = header.split(nil, 2)
			CONNECTION_REGEXP =~ header
			connection = nil
			connection = Regexp.last_match(1) unless Regexp.last_match.nil?

			# rewrite connection header
			data.sub(/Connection: /i, "Proxy-Connection: ") unless connection.nil?
			#p "Connection_persistency: %s" % @persistent

			/^(.*)\r?\n/ =~ header
			request_string = Regexp.last_match(1).strip
			method, uri, http_version = request_string.split("\s", 3)
			parsed_uri = URI.parse(uri)
			data = data.sub(uri, parsed_uri.path)
		else
			#p "*** continued ***"
			body = data
		end

		# send back response to client
		@request_handler.send_data(data)
	end

	def connection_completed
		p "connection established to server: #{@request_handler.id}"
	end

	def unbind
		p "unbind from server"
		issue_shutdown_signal
		@state = :closed
	end

	def issue_shutdown_signal
		@request_handler.handle_shutdown_signal unless @active_close
	end

	def handle_shutdown_signal
		@active_close = true
		close_connection_after_writing unless @state == :closed
	end
end

class RequestHandler < EM::Connection
	attr_reader :id

	def initialize
		@upstream = nil
		@host = @port = nil
		@state = :not_connected
	end

	def post_init
	end

	def receive_data(data)
		if !@upstream.nil? && @upstream.mode == :tunnel then
			@upstream.send_data(data)
			return
		end
		header, body = data.split("\r?\n\r?\n", 2)

		# parse request string
		/^(.*)\r?\n/ =~ header
		request_string = Regexp.last_match(1).strip
		method, uri, http_version = request_string.split("\s", 3)

		# parse connection header
		PROXY_CONNECTION_REGEXP =~ header
		proxy_connection = !Regexp.last_match.nil? unless Regexp.last_match.nil?

		if method == "CONNECT" then
			# CONNECT method
			host, port = uri.strip.split(":", 2)
			@upstream = EM.connect(host, port, Upstream, self)
			# rewrite connection header
			data.sub(/Proxy-Connection: /i, "Connection: ") unless proxy_connection.nil?
			# send through upstream socket
			@upstream.create_tunnel(data)
		else
			# Other method
			uri = URI.parse(uri)
			if @upstream == nil then
				@upstream = EM.connect(uri.host, uri.port, Upstream, self)
				@host, @port = uri.host, uri.port
			end
			if uri.host != @host || uri.port != @port then
				@upstream.close_connection
				@upstream = EM.connect(uri.host, uri.port, Upstream, self)
				@host, @port = uri.host, uri.port
			end
			# rewrite connection header
			data.sub(/Proxy-Connection: /i, "Connection: ") if proxy_connection
			# send through upstream socket
			@upstream.send_data(data)
		end
	end

	def connection_completed
		peeraddr = Socket.unpack_sockaddr_in(get_peername)
		@id = peeraddr[1]
		@state = :connected
		p "connection established to browser: #{peeraddr}"
	end

	def unbind
		p "unbind from browser"
		issue_shutdown_signal
		@state = :closed
	end

	def issue_shutdown_signal
		p @upstream
		@upstream.handle_shutdown_signal unless @active_close || @upstream.nil?
	end

	def handle_shutdown_signal
		@active_close = true
		close_connection_after_writing unless @state == :closed
	end
end
