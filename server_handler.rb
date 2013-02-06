require 'uri'
require 'socket'
require './nsa_utils'

CONNECTION_REGEXP        = /^Connection:\s*([\S]+)/i.freeze
PROXY_CONNECTION_REGEXP  = /^Proxy-Connection:\s([\S]+)$/i.freeze

class Upstream < EM::Connection
	attr_reader :mode
	attr_accessor :host
	attr_accessor :port

	def initialize(downstream, id)
		@downstream = downstream
		@id = id
		@host, @port = nil
		@mode = :proxy
		@state = :not_connected
	end

	def post_init
		@state = :connected
	end

	def create_tunnel(data)
		@mode = :tunnel
		response = "HTTP/1.1 200 connection established\r\n\r\n"
		@downstream.send_data_with_id(response, @id)
	end

	def receive_data(data)
		p "received response; data: #{data.bytesize}, sess_id: #{@id}"
		if @mode == :tunnel then
			@downstream.send_data_with_id(data, @id)
			return
		end

		if data.byteslice(0,10) =~ /^HTTP\/1.\d\s.*/i then
			header, body = data.split(/\r?\n\r?\n/, 2)
			http_version, _ = header.split(nil, 2)
			CONNECTION_REGEXP =~ header
			connection = nil
			connection = Regexp.last_match(1) unless Regexp.last_match.nil?

			# rewrite connection header
			data.sub!(/Connection: /i, "Proxy-Connection: ") unless connection.nil?

			/^(.*)\r?\n/ =~ header
			request_string = Regexp.last_match(1).strip
			method, uri, http_version = request_string.split("\s", 3)
			parsed_uri = URI.parse(uri)
			data = data.sub(uri, parsed_uri.path)
		end

		# send back response to client
		@downstream.send_data_with_id(data, @id)
	end

	def unbind
		@downstream.issue_shutdown_signal(@id) unless @active_close
		@state = :closed
	end

	def handle_shutdown_signal
		@active_close = true
		close_connection_after_writing unless @state == :closed
	end
end

class NSAServer < EM::Connection
	include NSAUtils

	def initialize
		@upstreams = Hash.new
	end

	def send_data_with_id(data, id, flag="\x00")
		packed_data = pack_header(data, id, flag)
		p "sending back response; data: #{data.bytesize}, id: #{id}"
		send_data(packed_data)
	end

	def receive_data(packed_data)
		id, flag, data = unpack_header(packed_data)
		@upstreams[id].handle_shutdown_signal if flag == "\x10" && !@upstreams[id].nil?
		return if data.bytesize == 0
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

		if method =~ /CONNECT/i then
			# CONNECT method
			host, port = uri.strip.split(":", 2)
			@upstreams[id] = EM.connect(host, port, Upstream, self, id)
			# rewrite connection header
			data.sub!(/Proxy-Connection: /i, "Connection: ") unless proxy_connection
			# send through upstream socket
			@upstreams[id].create_tunnel(data)
		else
			# Other method
			uri = URI.parse(uri)
			if @upstreams[id] == nil then
				@upstreams[id] = EM.connect(uri.host, uri.port, Upstream, self, id)
				@upstreams[id].host, @upstreams[id].port = uri.host, uri.port
			end
			if uri.host != @upstreams[id].host || uri.port != @upstreams[id].port then
				@upstreams[id].close_connection
				@upstreams[id] = EM.connect(uri.host, uri.port, Upstream, self, id)
				@upstreams[id].host, @upstreams[id].port = uri.host, uri.port
			end
			# rewrite connection header
			data.sub!(/Proxy-Connection: /i, "Connection: ") if proxy_connection
			# send through upstream socket
			@upstreams[id].send_data(data)
		end
	end

	def unbind
		# TODO 終了処理
	end

	def issue_shutdown_signal(id)
		send_data_with_id("", id, "\x10")
	end
end
