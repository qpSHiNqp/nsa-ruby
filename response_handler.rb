CONNECTION_REGEXP  = /^Connection:\s([\S]+)$/i.freeze

class ResponseHandler
    attr_reader :rewrited_response

    def initialize
        @payload = nil
    end

    def parse(payload)
        @payload = payload

        http_version, _ = payload.split(/\s/, 2)

        tmp = @payload
        if http_version =~ /HTTP\/1\.\d/i then
            header, body = @payload.split(/\r?\n\r?\n/, 2)
            CONNECTION_REGEXP =~ header
            @connection = nil
            @connection = Regexp.last_match(1) unless Regexp.last_match.nil?

            tmp.sub!(/Connection: /i, "Proxy-Connection: ") unless @connection.nil?
        end
        @rewrited_response = tmp
        return tmp
    end

#    def persistent?(http_version, proxy_connection)
#        if http_version == HTTP_1_0
#            proxy_connection =~ KEEP_ALIVE_REGEXP
#        else
#            proxy_connection.nil? || proxy_connection !~ CLOSE_REGEXP
#        end
#    end
end
