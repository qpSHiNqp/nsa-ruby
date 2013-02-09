require "uri"
require "./nsa_utils"
require "eventmachine"

CONNECTION_REGEXP        = /^Connection:\s*([\S]+)/i.freeze
PROXY_CONNECTION_REGEXP  = /^Proxy-Connection:\s([\S]+)$/i.freeze

class NSAServerUpstream < EM::Connection
	attr_reader :mode
	attr_accessor :host
	attr_accessor :port

	def initialize(downstream, id)
		@downstream = downstream
		@id = id
		@host, @port = nil, nil
		@mode = :proxy
		@state = nil
		@active_close = false
	end # initialize

	def post_init
		@state = :connected
	end # post_init

	def create_tunnel
		@mode = :tunnel
		@downstream.send_data("HTTP/1.1 200 Connection established\r\n\r\n", @id)
	end # create_tunnel

	def receive_data(data)
		if @mode != :tunnel && data.byteslice(0, 10) =~ /^HTTP\/1\.\d\s.*/i then
			header, body = data.split("\r?\n\r?\n", 2)
			CONNECTION_REGEXP =~ header
			connection = nil
			connection = Regexp.last_match(1) unless Regexp.last_match.nil?
			data.sub!(/Connection: /i, "Proxy-Connection: ") unless connection.nil?
		end
		@downstream.send_data(data, @id)
	end # receive_data

	def unbind
		@downstream.issue_shutdown_signal(@id) unless @active_close
		@state = :closed
	end # unbind

	def handle_shutdown_signal
		@active_close = true
		close_connection_after_writing unless @state == :closed
	end # handle_shutdown_signal
end # NSAServerUpstream

class NSAServerDownstream < EM::Connection
	include NSAUtils

	def initialize
		@upstreams = Hash.new # session table
	end # initialize

	def send_data(data, id, flag="\x00")
		super pack_header(data, id, flag)
	end # send_data (override)

	def receive_data(data)
		id, flag, data = unpack_header(data)
		request_header = true
		p "#{id}: #{data.byteslice(0,80)}"

		@upstreams[id].handle_shutdown_signal if (flag == "\x10" && !@upstreams[id].nil?)
		return if data.bytesize == 0

		if !@upstreams[id].nil? && @upstreams[id].mode == :tunnel then
			@upstreams[id].send_data(data)
			return
		end

		# parse request string
		header, body = data.split("\r?\n\r?\n", 2)
		/^(.*)\r?\n/ =~ header
		if Regexp.last_match.nil? then
			request_header = false
		else
			request_string = Regexp.last_match(1).strip
			method, uri, http_version = request_string.split("\s", 3)

			# parse connection header
			PROXY_CONNECTION_REGEXP =~ header
			proxy_connection = !Regexp.last_match.nil? unless Regexp.last_match.nil?
			data.sub!(/Proxy-Connection: /i, "Connection: ") if proxy_connection
		end

		if method =~ /CONNECT/i then
			host, port = uri.strip.split(":", 2)
			@upstreams[id] = EM.connect(host, port, NSAServerUpstream, self, id)
			@upstreams[id].create_tunnel
		elsif request_header then
			parsed_uri = URI.parse(uri)
			if @upstreams[id].nil? then
				@upstreams[id] = EM.connect(parsed_uri.host, parsed_uri.port, NSAServerUpstream, self, id)
				@upstreams[id].host, @upstreams[id].port = parsed_uri.host, parsed_uri.port
			elsif parsed_uri.host != @upstreams[id].host || parsed_uri.port != @upstreams[id].port then
				@upstreams[id].close_connection
				@upstreams[id] = EM.connect(parsed_uri.host, parsed_uri.port, NSAServerUpstream, self, id)
				@upstreams[id].host, @upstreams[id].port = parsed_uri.host, parsed_uri.port
			end
			data.sub!(uri, parsed_uri.path)
			@upstreams[id].send_data(data)
		else
			@upstreams[id].send_data(data)
		end
	end # receive_data

	def unbind
		EM.stop
	end # unbind

	def issue_shutdown_signal(id)
		send_data("", id, "\x10")
	end # issue_shutdown_signal
end # NSAServerDownstream
