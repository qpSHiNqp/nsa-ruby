require "socket"
require "./nsa_utils"

class Session
    attr_reader :id
    attr_reader :host
    attr_accessor :sock

    def initialize(sock)
        @sock = sock
        peeraddr = Socket.unpack_sockaddr_in(sock.getsockname)
        @id = peeraddr[1].to_i
        @host = peeraddr[0]

        p [@sock, @id, @host]
    end
end

class NSAClient
    include NSAUtils

    def initialize(server_addr, server_port, listen_port)
        @up_sock = TCPSocket.open(server_addr, server_port)
        @listen_sock = TCPServer.open(listen_port)
        @socks = [@up_sock, @listen_sock]
        @ids = Hash.new
        @sessions = Hash.new
    end

    def run
        loop do
            s = select(@socks)
            s[0].each do |sock|
                case sock
                when @listen_sock
                    accept_new_connection
                when @up_sock
                    _log "Received response from server"
                    data = sock.recv(65536)
                    if data.bytesize == 0 then
                        reconnect
                    else
                        id, flag, payload = unpack_header(data)
                        if flag == "\x10" then
                            shutdown
                        end
                        @sessions[id].sock.write payload unless payload.bytesize == 0
                    end
                else
                    _log "Received request from browser"
                    id = @ids[sock]
                    data = sock.recv(65536)
                    if data.bytesize == 0 then
                        shutdown
                    else
                        @up_sock.write pack_header(data, id)
                    end
                end
            end
        end
    end

    def accept_new_connection
        ns = @listen_sock.accept
        @socks.push(ns)
        sess = Session.new(ns)
        @sessions[sess.id] = sess
        @ids[ns] = sess.id
        _log "Accepted new connection from browser"
    end

    def shutdown
    end

    def reconnect
    end
end

nsa_sock = NSAClient.new("localhost", 50000, 8080)
nsa_sock.run
