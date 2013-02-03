require 'uri'
require 'socket'

HTTP_1_0                 = 'HTTP/1.0'.freeze
CONNECTION_REGEXP        = /^Connection:\s*([\S]+)/i.freeze
PROXY_CONNECTION_REGEXP  = /^Proxy-Connection:\s([\S]+)$/i.freeze
KEEP_ALIVE_REGEXP        = /\bkeep-alive\b/i.freeze
CLOSE_REGEXP             = /\bclose\b/i.freeze
CONTENT_LENGTH_REGEXP    = /^Content-Length:\s+(\d+)/i.freeze
TRANSFER_ENCODING_REGEXP = /^Transfer-Encoding:\s*(\w+)/i.freeze

class Upstream < EM::Connection
	attr_reader :mode

	def initialize(downstream, id)
		@downstream = downstream
		@id = id
		@mode = :proxy
		@state = :not_connected
	end

	def post_init
		@state = :connected
	end

	def create_tunnel(data)
		@mode = :tunnel
		response = "HTTP/1.1 200 connection established\r\n\r\n"
		@downstream.send_data(response, @id)
	end

	def send_data(data)
		p data
		super data
	end

	def receive_data(data)
		if @mode == :tunnel then
			@downstream.send_data(data, @id)
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
		@downstream.send_data(data, @id)
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
		@downstream.issue_shutdown_signal(@id) unless @active_close
	end

	def handle_shutdown_signal
		@active_close = true
		close_connection_after_writing unless @state == :closed
	end
end

class NSAServer < EM::Connection
	def initialize
		@upstreams = Hash.new
		@host = @port = nil
		@state = :not_connected
	end

	def send_data(data, id, flag = "\x00")
		data = pack_header(data, id, flag)
		super(data)
	end

	def receive_data(data)
		id, flag, data = unpack_header(data)
		@upstreams[id].handle_shutdown_signal if flag == "\x10"
		if !@upstreams[id].nil? && @upstreams[id].mode == :tunnel then
			@upstreams[id].send_data(data)
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
			@upstreams[id] = EM.connect(host, port, Upstream, self, id)
			# rewrite connection header
			data.sub(/Proxy-Connection: /i, "Connection: ") unless proxy_connection.nil?
			# send through upstream socket
			@upstreams[id].create_tunnel(data)
		else
			# Other method
			uri = URI.parse(uri)
			if @upstreams[id] == nil then
				@upstreams[id] = EM.connect(uri.host, uri.port, Upstream, self, id)
				@host, @port = uri.host, uri.port
			end
			if uri.host != @host || uri.port != @port then
				@upstreams[id].close_connection
				@upstreams[id] = EM.connect(uri.host, uri.port, Upstream, self, id)
				@host, @port = uri.host, uri.port
			end
			# rewrite connection header
			data.sub(/Proxy-Connection: /i, "Connection: ") if proxy_connection
			# send through upstream socket
			@upstreams[id].send_data(data)
		end
	end

	def unbind
		# TODO 終了処理
	end

	def issue_shutdown_signal(id)
		p @upstreams[id]
		send_data("", id, "\x10")
	end
end
