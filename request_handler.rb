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

    def initialize(request)
        @request = request
        # http header/bodyの分離
        @header, @body = @request.split(/\r?\n\r?\n/, 2)

        # Request string の解析
        /^(.*)\r?\n/ =~ @header
        if !Regexp.last_match.nil? then
            @request_string = Regexp.last_match(1).strip
            @http_method, @uri, @http_version = @request_string.split("\s", 3)

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
            end
        end

        # parse connection header
        PROXY_CONNECTION_REGEXP =~ @header
        @proxy_connection = !Regexp.last_match.nil? unless Regexp.last_match.nil?
    end

    def proxy_rewrite
        tmp = @request.sub(@uri, @path)
        tmp.sub(/Proxy-Connection: /i, "Connection: ") if @proxy_connection
        return tmp
    end
end
