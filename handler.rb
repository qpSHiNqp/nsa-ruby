require 'uri'

HTTP_1_0                 = 'HTTP/1.0'.freeze
CONNECTION_REGEXP        = /^Connection:\s(\w+)$/i.freeze
PROXY_CONNECTION_REGEXP  = /^Proxy-Connection:\s(\w+)$/i.freeze
KEEP_ALIVE_REGEXP        = /\bkeep-alive\b/i.freeze
CLOSE_REGEXP             = /\bclose\b/i.freeze

class Upstream < EM::Connection
	def initialize(rh)
		@request_handler = rh
		@mode = :proxy
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
		send_data(data)
	end

	def receive_data(data)
		# keep-alive or not
		header, body = data.split("\r\n\r\n", 2)
		/^.*\s/ =~ header
		http_version = Regexp.last_match(1).strip
		CONNECTION_REGEXP =~ header
		connection = nil
		connection = Regexp.last_match(1) if !Regexp.last_match.nil?

		# rewrite connection header
		data.sub(/Connection: /i, "Proxy-Connection: ") if proxy_connection

		# send back response to client
		@request_handler.send_data(data)

		# connection: close
		@request_handler.close_connection_after_writing if !persistent?(connection, http_version)
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
		header, body = data.split("\r\n\r\n", 2)

		# parse request string
		/^.*\r\n/ =~ header
		request_string = Regexp.last_match(0).strip
		method, uri, http_version = request_string.split("\s")
		p [method, uri, http_version]

		# parse connection header
		PROXY_CONNECTION_REGEXP =~ header
		proxy_connection = !Regexp.last_match.nil?

		if method == "CONNECT" then
			# CONNECT method
			uri = URI.parse(uri)
			@upstream = EM.connect(uri.host, uri.port, Upstream, self)
			# rewrite connection header
			data.sub(/Proxy-Connection: /i, "Connection: ") if proxy_connection
			# send through upstream socket
			@upstream.create_tunnel(data)
		else
			# Other method
			if @upstream == nil then
				uri = URI.parse(uri)
				@upstream = EM.connect(uri.host, uri.port, Upstream, self)
			end
			if @upstream.mode == :tunnel then
				# pass the request through the tunnel
				@upstream.send_data(data)
			else
				# rewrite connection header
				data.sub(/Proxy-Connection: /i, "Connection: ") if proxy_connection
				end
				# send through upstream socket
				@upstream.send_data(data)
			end
		end
	end

	def unbind
		@upstream.close_connection_after_writing if !@upstream.nil?
	end
end
