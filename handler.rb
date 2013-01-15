require 'uri'

HTTP_1_0                 = 'HTTP/1.0'.freeze
CONNECTION_REGEXP        = /^Connection:\s*([\S]+)/i.freeze
PROXY_CONNECTION_REGEXP  = /^Proxy-Connection:\s([\S]+)$/i.freeze
KEEP_ALIVE_REGEXP        = /\bkeep-alive\b/i.freeze
CLOSE_REGEXP             = /\bclose\b/i.freeze
CONTENT_LENGTH_REGEXP    = /^Content-Length:\s+(\d+)/i.freeze
TRANSFER_ENCODING_REGEXP = /^Transfer-Encoding:\s*(\w+)/i.freeze

class Upstream < EM::Connection
	attr_reader :mode

	def initialize(rh)
		@request_handler = rh
		@mode = :proxy
		@persistent = true
	end

	def post_init
		#p "<<< in post_init >>>"
		@content_length = 0
		@received = 0
		@chunked = false
		@chunk_received = 0
	end

	def persistent?(http_version, proxy_connection)
		if http_version == HTTP_1_0
			proxy_connection =~ KEEP_ALIVE_REGEXP
		else
			proxy_connection.nil? || proxy_connection !~ CLOSE_REGEXP
		end
	end

	def create_tunnel(data)
		@mode = :tunnel
		response = "HTTP/1.1 200 connection established\r\n\r\n"
		@request_handler.send_data(response)
	end

	def receive_data(data)
		if @mode == :tunnel then
			@request_handler.send_data(data)
			return
		end

		chunk_end = false
		body = ""

		if @content_length == 0 && !@chunked then
			# keep-alive or not
			header, body = data.split(/\r?\n\r?\n/, 2)
			#p "==============================="
			p header
			http_version, pseudo = header.split(nil, 2)
			CONNECTION_REGEXP =~ header
			connection = nil
			connection = Regexp.last_match(1) unless Regexp.last_match.nil?

			# content length
			CONTENT_LENGTH_REGEXP =~ header
			@content_length = Regexp.last_match.nil? ? 0 : Regexp.last_match(1).to_i
			#p "content-length: %s" % @content_length

			# chunked?
			TRANSFER_ENCODING_REGEXP =~ header
			@chunked = Regexp.last_match.nil? ? false : true
			#p "chunked?: %s" % @chunked

			# persistent?
			@persistent = persistent?(connection, http_version)

			# rewrite connection header
			data.sub(/Connection: /i, "Proxy-Connection: ") unless connection.nil?
			p "Connection: %s" % connection
		else
			#p "*** continued ***"
			body = data
		end
		if @chunked then
			chunk = body
			while true do
				chunk_size, message = chunk.split(/\r?\n/, 2)
				if chunk_size.strip == "0" then
					chunk_end = true
					break
				end
				chunk_size = chunk_size.hex
				p "*** (chunk: %d bytes)" % chunk_size
				p message
				if message.nil? || message.bytesize == 0 then
					@chunk_received = 0
					break
				elsif message.bytesize >= chunk_size then
					chunk = message.byteslice(chunk_size, message.bytesize - chunk_size)
					@chunk_received = 0
				else
					@chunk_received = @chunk_received + message.bytesize
					break
				end
			end
		end
		#p ">>> body size: %d" % body.bytesize

		# send back response to client
		@request_handler.send_data(data)
		@received = @received + body.bytesize

		if (@received >= @content_length && ! @chunked) || chunk_end then
			#p "*** finished receive body (chunk_end: %s) ***" % chunk_end
			# connection: close
			@request_handler.close_connection_after_writing unless @persistent
			post_init
		end
	end

	def unbind(data)
		@request_handler.close_connection_after_writing
	end
end

class RequestHandler < EM::Connection
	def initialize
		@upstream = nil
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
		p request_string

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
			if @upstream == nil then
				uri = URI.parse(uri)
				@upstream = EM.connect(uri.host, uri.port, Upstream, self)
			end
			# rewrite connection header
			data.sub(/Proxy-Connection: /i, "Connection: ") if proxy_connection
			# send through upstream socket
			@upstream.send_data(data)
		end
	end

	def unbind
		@upstream.close_connection_after_writing unless @upstream.nil?
	end
end
