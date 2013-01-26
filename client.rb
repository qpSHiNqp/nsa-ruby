# client.rb
# ┌───────────┬─┬────────┐
# │desc(2byte)│f│data    │
# └───────────┴─┴────────┘
# graceful close flag(0x001)が1ならば, requestキューが空の場合はコネクションをcloseしようとする
# forceful close flag(0x010)が1ならば, 強制的にコネクションclose
# response complete flag(0x100)が1ならば, requestキューから1つpopする
# establish flag(0x1000)が1ならば, 新規セッションであることをserverへ通知

require "socket"
require "./nsa_utils"

SERVER_ADDR = "127.0.0.1".freeze
SERVER_PORT = 20000.freeze
PROXY_PORT = 8080.freeze

class NSAClient
    include NSAUtils

    def initialize(server_addr, server_port, listen_port)
        @upstream_socket = TCPSocket.open(server_addr, server_port)
        _log "Established NSA Session to server: #{@upstream_socket.peeraddr[2]}\n"
        @listen_socket = TCPServer.open(listen_port)
        @descriptors = [@upstream_socket, @listen_socket]
        @ids = Hash.new
    end # initialize

    def run
        loop do
            s = IO::select(@descriptors)
            s[0].each do |sock|
                case sock
                when @listen_socket
                    accept_new_connection
                when @upstream_socket # NSAServerからのresponse
                    data = sock.recv(65536)
                    reconnect(sock) if data.length == 0
                    id, flag, payload = unpack_header(data)
                    @ids[id].write(payload) unless payload.bytesize == 0
                    unsubscribe_connection(@ids[id], true) if flag == "\x10"
                else # Browserからのrequest
                    _log "Received data from browser\n"
                    # session id は接続元port番号
                    payload = sock.recv(65536)
                    if payload.length == 0 then
                        # connection is closed by the browser
                        unsubscribe_connection(sock)
                        next
                    end

                    @upstream_socket.write pack_header(payload, sock.peeraddr[1])
                    _log "sent request to server\n"
                end
            end # each
        end # loop
    end # run

    def stop
        @descriptors.each do |s|
            s.close
        end
    end # stop

    private

    def reconnect(sock)
        host, port = sock.peeraddr[2], sock.peeraddr[1]
        @descriptors.delete(sock)
        sock.close
        sock = TCPSocket.open(host, port)
        @descriptors.push(sock)
    end

    def accept_new_connection
        newsock = @listen_socket.accept
        @descriptors.push(newsock)
        @ids[newsock.peeraddr[1]] = newsock
        _log "accepted new connection from #{newsock.peeraddr[2]}\n"
    end # accept_new_connection

    def unsubscribe_connection(sock, shutdown=false)
        if shutdown then
            sock.shutdown unless sock.closed? || sock.eof?
        else
            if sock != @upstream_socket then
                @upstream_socket.write pack_header("", (sock.peeraddr)[1], "\x10")
            end
            sock.close
            @descriptors.delete(sock)
        end
    end # unsubscribe_connection
end # class NSAClient

#################
# startup
#################
worker = NSAClient.new(SERVER_ADDR, SERVER_PORT, PROXY_PORT)
Signal.trap("INT") { worker.stop }
Signal.trap("TERM") { worker.stop }
worker.run
