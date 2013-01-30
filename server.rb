require "socket"
require "./nsa_utils"

class Session
    attr_accessor :sock
    attr_reader :host
    attr_reader :port
    attr_reader :id

    def initialize(sock)
        @sock = sock
    end
end

class NSAWorker
    include NSAUtils

    def initialize(sock)
        @req = Parser.new
        @down_sock = sock
        @socks = [sock]
    end

    def run
        loop do
            s = select(@socks)
            s[0].each do |sock|
                case sock
                when @down_sock
                    # request from browser
                    data = sock.recv(65536)
                    if data.bytesize == 0 then
                        stop
                        next
                    end
                    id, flag, data = unpack_header(data)
                    @req.parse(data)
                    sess = @sessions[id]
                    if sess.nil? then
                        establish_new_session(sock, id, @req.host, @req.port)
                    elsif sess.host != @req.host || sess.port != @req.port then
                        update_session(sock, id, @req.host, @req.port)
                    end
                    sess.sock.write @req.rewrite unless payload.bytesize == 0
                    if flag == "\x10" then
                        shutdown
                    end
                else
                    # response from origin
                    data = sock.recv(65536)
                    if data.bytesize == 0 then
                        shutdown
                        next
                    end
                    @res.parse(data)
                    @down_sock.write pack_header(@res.rewrite, id) unless payload.bytesize == 0
                end # case
            end # each
        end # loop
    end # run

    def stop
    end

    def shutdown
    end
end

listen_sock = TCPServer.open(50000)
Socket.accept_loop(listen_sock) do |sock|
    fork do
        worker = NSAWorker.new(sock)
        worker.run
    end # fork
end # accept loop
