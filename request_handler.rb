require "uri"

PROXY_CONNECTION_REGEXP  = /^Proxy-Connection:\s([\S]+)$/i.freeze

class RequestHandler
    attr_reader :request
    attr_reader :header
    attr_reader :body
    attr_reader :request_string
    attr_reader :http_method
    attr_reader :uri
    attr_reader :http_version
    attr_reader :host
    attr_reader :port
    attr_reader :path
    attr_reader :proxy_connection
    attr_reader :rewrited_request

    def initialize
        @request = nil
    end

    def parse(request)
        @request = request
        @rewrited_request = @request

        # Request Stringの有無の判定
        @http_method, @uri, @http_version, _ = @request.split(/\s/, 4)
        if @http_version =~ /HTTP\/1\.\d/i then
            @header, @body = @request.split(/\r?\n\r?\n/, 2)

            # parse connection header
            PROXY_CONNECTION_REGEXP =~ @header
            @proxy_connection = !Regexp.last_match.nil? unless Regexp.last_match.nil?

            if @http_method =~ /CONNECT/i then
                @host, @port = @uri.split(":")
                @path = nil
            else
                begin
                    uri_parsed = URI.parse(@uri)
                rescue URI::InvalidURIError
                    print "URI Error occurred: "
                    p @uri
                end
                @host, @port = uri_parsed.host, uri_parsed.port
                @path = uri_parsed.path
                @rewrited_request = @request.sub!(@uri, @path)
            end
            @rewrited_request.sub!(/Proxy-Connection: /i, "Connection: ") if @proxy_connection
        else
            @http_method = @uri = @http_version = nil
        end
        return @rewrited_request
    end
end
