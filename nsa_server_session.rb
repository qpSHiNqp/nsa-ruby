require "socket"

class NSAServerSession
    attr_accessor :state
    attr_accessor :sock
    attr_accessor :id
    attr_accessor :mode
    attr_reader :host
    attr_reader :port

    def initialize(id, data)
        @id = id
        @mode = :normal

        @host, @port = remotehost(data)
        @sock = TCPSocket.open(@host, @port)
        @state = :established
    end # initialize

    def location_change?(data)
        return false if @mode == :tunnel
        return false if request?(data)
        host, port = remotehost(data)
        if host != @host || port != @port then
            return true
        end
        return false
    end

    def request?(data)
        method = data.split[0]
        if method =~ /(GET|POST|PUT|DELETE|CONNECT|HEAD|OPTIONS|TRACE|PATCH|LINK|UNLINK|PROPFIND|PROPPATCH|MKCOL|COPY|MOVE|LOCK)/i then
            return true
        else
            return false
        end
    end

    def remotehost(data)
        uri = data.split[1]
        if uri =~ /\// then
            host, port = uri.split("//")[1].split("/")[0].split(":")
        else
            host, port = uri.split(":")
        end
        port = "80" if port.nil?
        return [host, port.to_i]
    end # remotehost

    def proxy_rewrite(data)
        method, uri, path, status = parse(data)
        if status.nil then
            if method.nil? then
                return data
            end
            # request
            @mode = :tunnel if method =~ /CONNECT/i
            return data if @mode == :tunnel

            # Proxy-Connection
            data = data.sub(/Proxy-Connection: /i, "Connection: ") if data =~ /\s+Proxy-Connection: .*\r?\n\r?\n/i
            return data.sub(uri, path)
        else
            # response
            return data if @mode == :tunnel

            # Proxy-Connection
            data = data.sub(/Connection: /i, "Proxy-Connection: ") if data =~ /\s+Connection: .*\r?\n\r?\n/i
            return data
        end
    end # proxy_rewrite

    def parse(data)
        status = data.sub(/.*\s(\d{3})\s.*/, "\\1")
        if status.nil? then
            arr = data.split[0]
            hostpatharr = arr[1].split(/:\/\//)
            if hostpatharr.length == 2 then
                tmp = hostpatharr[1]
            else
                tmp = hostpatharr[0]
            end
            host, path = hostpatharr.split("/", 2)
            return [arr[0], arr[1], "/" + path, nil]
        else
            return [nil, nil, nil, status]
        end
    end # parse
end # class NSAServerSession
