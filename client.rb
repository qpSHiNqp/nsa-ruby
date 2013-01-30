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

SERVER_ADDR = "localhost".freeze
SERVER_PORT = 20000.freeze
PROXY_PORT = 8080.freeze

class NSAClient
    include NSAUtils

    def initialize(server_addr, server_port, listen_port)
        @upstream_socket = TCPSocket.open(server_addr, server_port)
        _log "Established NSA Session to server: #{@upstream_socket.peeraddr[2]}\n"
        @listen_socket = TCPServer.open(listen_port)
        @descriptors = [@upstream_socket, @listen_socket]
        @ports = Hash.new
        @ids = Hash.new
        @state = Hash.new
    end # initialize

    def run
        loop do
            s = IO::select(@descriptors)
            s[0].each do |sock|
                case sock
                when @listen_socket
                    accept_new_connection
                when @upstream_socket # NSAServerからのresponse
                    _log "Received response from server"
                    data = sock.recv(65536)
                    reconnect(sock) if data.length == 0
                    id, flag, payload = unpack_header(data)
                    @ids[id].write(payload) unless payload.bytesize == 0 || @ids[id].nil?
                    graceful_close(@ids[id]) if flag == "\x10" && !@ids[id].nil?
                else # Browserからのrequest
                    _log "Received data from browser\n"
                    # session id は接続元port番号
                    begin
                        payload = sock.recv(65536)
                    rescue Errno::ECONNRESET
                        unsubscribe_connection sock
                    end
                    if payload.length == 0 then
                        # connection is closed by the browser
                        unsubscribe_connection sock
                        next
                    end

                    _log payload[0, 80], "Debug"
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

    def unsubscribe_connection(sock)
        id = @ports[sock]
        _log "Closed connection to browser: #{id}\n"
        if @state[id] == :half_close then
            @state.delete(id)
        else
            @state[id] = :half_close
            @upstream_socket.write pack_header("", id, "\x10")
        end
        @ids.delete(id)
        @descriptors.delete(sock)
        sock.close
    end

    def graceful_close(sock)
        _log "closing connection"
        id = @ports[sock]
        begin
            if @state[id] == :half_close then
                @state.delete(id)
            else
                sock.shutdown
                @state[id] = :half_close
            end
        rescue
            _log "Connection is already closed", "Warn"
        end
    end

    def reconnect(sock)
        _log "Reconnecting to server"
        peeraddr = sock.getpeername
        host, port = peeraddr[0], peeraddr[1].to_i
        @descriptors.delete(sock)
        sock.close
        sock = TCPSocket.open(host, port)
        @descriptors.push(sock)
    end

    def accept_new_connection
        newsock = @listen_socket.accept
        @descriptors.push(newsock)
        peeraddr = newsock.getpeername
        id = peeraddr[1].to_i
        @ports[newsock] = id
        @ids[id] = newsock
        @state[id] = :established
        _log "accepted new connection from #{peeraddr[0]}\n"
    end # accept_new_connection

end # class NSAClient

#################
# startup
#################
worker = NSAClient.new(SERVER_ADDR, SERVER_PORT, PROXY_PORT)
Signal.trap("INT") { worker.stop }
Signal.trap("TERM") { worker.stop }
worker.run
