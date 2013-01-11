require 'rubygems'
require 'eventmachine'
require './parser.rb'

# Freeze some HTTP header names & values
KEEPALIVE = "Connection: Keep-Alive\r\n".freeze

class Connector < EM::Connection
	def initialize(request_handler)
		@request_handler = request_handler
	end

	def post_init
	end

	def send_request
		p @request_handler.req.to_s
		send_data(@request_handler.req.to_s)
	end

	def receive_data(data)
		keep_alive = @request_handler.req_parser.persistent?
		@request_handler.handle_http_response(data)
		
		if keep_alive
			post_init
		else
			close_connection_after_writing
		end
	end
end

class TunnelHandler < EM::Connection
	def initialize(request_handler)
		@request_handler = request_handler
	end

	def post_init
	end

	def send_connect_request(raw_request)
	end

	def pass_through(data)
		send_data(data)
	end

	def receive_data(data)
		@request_handler.pass_through(data)
	end
end

class RequestHandler < EM::Connection
	attr_reader :req
	attr_reader :req_parser

	def initialize
		@tunnel = nil
	end

	def post_init
		@req_parser = RequestParser.new
		@request_string = nil
		@req = nil
	end

	def receive_data(data)
		if @tunnel == nil then
			@request_string = data
			#p @request_string
			handle_http_request if @req_parser.parse(data)
		else
			@tunnel.pass_through(data)
		end
	end

	def handle_http_request
		keep_alive = @req_parser.persistent?

		case (@req_parser.request[:method])
		when "CONNECT"
			# トンネリング処理
			handle_connect_request
		else
			# @request_stringの書き換え
			@req = @req_parser.clone
			@req.request[:uri] = @req_parser.uri.path
			@req.header["Connection"] = @req_parser.header["Proxy-Connection"] if @req.header["Proxy-Connection"] != nil
			@req.header.delete("Proxy-Connection")
			# Oへrequest送信
			@connector = EM.connect(@req_parser.uri.host, @req_parser.uri.port, Connector, self)
			@connector.send_request

			if keep_alive
				post_init
			else
				close_connection_after_writing
			end
		end
	end

	def handle_connect_request
		@tunnel = EM.connect(@req_parser.uri.host, @req_parser.uri.port, TunnelHandler, self)
		@tunnel.send_connect_request(@request_string)
	end

	def handle_http_response(data)
		p data
		header, body = data.split("\r\n\r\n")
		if header =~ /^Connection: / then
			data.sub!(/^Connection: /, "Proxy-Connection: ")
		end
		send_data(data)
	end

	def pass_through(data)
		send_data(data)
	end
end

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
