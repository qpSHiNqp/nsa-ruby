PROXY_CONNECTION_REGEXP  = /^Proxy-Connection:\s([\S]+)$/i.freeze

class RequestHandler
    def initialize(request)
        @request = request
        # http header/bodyの分離
        @header, @body = data.split("\r?\n\r?\n", 2)

        # Request string の解析
        /^(.*)\r?\n/ =~ @header
        @request_string = Regexp.last_match(1).strip
        @method, @uri, @http_version = request_string.split("\s", 3)

        if @method =~ /CONNECT/i then
            @host, @port = uri.split(":")
            @path = nil
        else
            uri_parsed = URI.parse(uri)
            @host, @port = uri_parsed.host, uri_parsed.port
            @path = uri.path
        end

        # parse connection header
        PROXY_CONNECTION_REGEXP =~ header
        @proxy_connection = !Regexp.last_match.nil? unless Regexp.last_match.nil?
    end

    def proxy_rewrite
        tmp = @request.sub(uri, req.path)
        tmp.sub(/Proxy-Connection: /i, "Connection: ") if @proxy_connection
    end
end
