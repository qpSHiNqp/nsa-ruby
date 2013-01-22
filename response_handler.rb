CONNECTION_REGEXP  = /^Connection:\s([\S]+)$/i.freeze

class ResponseHandler
    def initialize(payload)
        @payload = payload
    end

    def proxy_rewrite(payload = nil)
        @payload = payload unless payload.nil?
        tmp = @payload
        # keep-alive or not
        header, body = @payload.split(/\r?\n\r?\n/, 2)
        http_version, pseudo = header.split(nil, 2)
        CONNECTION_REGEXP =~ header
        @connection = nil
        @connection = Regexp.last_match(1) unless Regexp.last_match.nil?

        tmp = tmp.sub(/Connection: /i, "Proxy-Connection: ") if @connection
        return tmp
    end

    def persistent?(http_version, proxy_connection)
        if http_version == HTTP_1_0
            proxy_connection =~ KEEP_ALIVE_REGEXP
        else
            proxy_connection.nil? || proxy_connection !~ CLOSE_REGEXP
        end
    end
end
