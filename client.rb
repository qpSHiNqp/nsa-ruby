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

SERVER_ADDR = "tanaka.hongo.wide.ad.jp".freeze
SERVER_PORT = 50000.freeze
PROXY_PORT = 8080.freeze

class NSAClient
    include NSAUtils

    def initialize(server_addr, server_port, listen_port)
        @upstream_socket = TCPSocket.open(server_addr, server_port)
        #_log "Established NSA Session to server: #{@upstream_socket.peeraddr[2]}\n"
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
                    _log "incoming SYN packet"
                    accept_new_connection
                when @upstream_socket # NSAServerからのresponse
                    received = 0
                    head = sock.recv(5)
                    reconnect(sock) if head.length == 0
                    id, flag, size = unpack_header(head)
                    payload = ""
                    _log "payload length: #{size}"
                    begin
                        payload += sock.recv(size - received)
                        received = payload.bytesize
                        _log "#{received} bytes received"
                    end while received < size
                    _log "Received response from server; id: #{id}"
                    #_log payload[0,80], "Debug"
                    @ids[id].write(payload) unless (payload.bytesize == 0 || @ids[id].nil?)
                    graceful_close(@ids[id]) if (flag == "\x10" && !@ids[id].nil?)
                else # Browserからのrequest
                    #_log "Received data from browser\n"
                    payload = ""
                    # session id は接続元port番号
                    begin
                        payload = sock.recv(65536)
                    rescue Errno::ECONNRESET
                        unsubscribe_connection sock
                    end
                    if payload.bytesize == 0 then
                        # connection is closed by the browser
                        unsubscribe_connection sock
                        next
                    end

                    _log payload[0, 80], "[#{sock.peeraddr[1]}]"
                    @upstream_socket.write pack_header(payload, sock.peeraddr[1])
                    #_log "sent request to server\n"

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
        id = @ports[sock.__id__]
        #_log "Closed connection to browser: #{id}\n"
        if @state[id] == :half_close then
            @state.delete(id)
        else
            @state[id] = :half_close
            @upstream_socket.write pack_header("", id, "\x10")
        end
        @ids.delete(id)
        @descriptors.delete(sock)
        begin
            sock.close
        rescue
        end
    end

    def graceful_close(sock)
        #_log "closing connection"
        id = @ports[sock.__id__]
        begin
            if @state[id] == :half_close then
                @state.delete(id)
            else
                sock.shutdown
                @state[id] = :half_close
            end
        rescue
            #_log "Connection is already closed", "Warn"
        end
    end

    def reconnect(sock)
        #_log "Reconnecting to server"
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
        peeraddr = Socket.unpack_sockaddr_in(newsock.getpeername)
        id = peeraddr[0].to_i
        @ports[newsock.__id__] = id
        @ids[id] = newsock
        @state[id] = :established
        _log "accepted new connection from #{peeraddr[0]}\n"
    end # accept_new_connection

end # class NSAClient

#################
# startup
#################
if ARGV.length > 0 then
    srv_addr = ARGV[0]
    srv_port = ARGV[1].to_i
else
    srv_addr = SERVER_ADDR
    srv_port = SERVER_PORT
end
worker = NSAClient.new(srv_addr, srv_port, PROXY_PORT)
#Signal.trap("INT") { worker.stop }
#Signal.trap("TERM") { worker.stop }
worker.run
