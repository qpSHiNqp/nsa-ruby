require 'uri'

HTTP_1_0          = 'HTTP/1.0'.freeze
PROXY_CONNECTION  = 'Proxy-Connection'.freeze
KEEP_ALIVE_REGEXP = /\bkeep-alive\b/i.freeze
CLOSE_REGEXP      = /\bclose\b/i.freeze

class RequestParser
	attr_accessor :request
	attr_accessor :header
	attr_accessor :uri

	def initialize
		@request = Hash.new
		@header = Hash.new
		@uri = nil
		@body = ""
	end

	def parse(req_str)
		req_str.each_line("") do |entity|
			if @uri == nil then
				entity.each_line("\r\n") do |line|
					line.chomp!
					next if line.length == 0
					if @uri == nil then
						@request[:method], @request[:uri], @request[:http_version] = line.split(/\s/, 3)
						@uri = URI.parse(@request[:uri].strip) if @request[:method] != "CONNECT"
					else
						key, value = line.split(/:\s*/, 2)
						@header[key] = value
					end
				end
			else
				@body = entity
			end
		end
		@request
	end

	def to_s
		request = @request.values.join(" ")
		header = Array.new
		@header.each do |key, value|
			begin
				header.push key + ": " + value
			rescue
				p key + " = " + value
			end
		end
		entity = [request].concat(header).concat([""]).concat([@body])
		entity.join("\r\n")
	end

	def persistent?
		if @request[:http_version] == HTTP_1_0
			@header[PROXY_CONNECTION] =~ KEEP_ALIVE_REGEXP
		else
			@header[PROXY_CONNECTION].nil? || @header[PROXY_CONNECTION] !~ CLOSE_REGEXP
		end
	end
end
