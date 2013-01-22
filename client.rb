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

DEBUG = true.freeze

SERVER_ADDR = "127.0.0.1".freeze
SERVER_PORT = 20000.freeze
PROXY_PORT = 8080.freeze

class NSAClient
    include NSAUtils

    def initialize(server_addr, server_port, listen_port)
        @upstream_socket = TCPSocket.open(server_addr, server_port)
        print "Established NSA Session to server: #{@upstream_socket.peeraddr[2]}\n"
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
                    reconnect(sock) unless alive_check sock, data
                    id, flag, payload = unpack_header(data)
                    @ids[id].write(payload)
                else # Browserからのrequest
                    print "Info: Received data from browser\n" if DEBUG
                    payload = ""
                    begin
                        # session id は接続元port番号
                        payload = sock.recv(65536)
                    rescue
                        print "Info: Recv failed\n" if DEBUG
                        next unless alive_check(sock, payload)
                    end
                    next unless alive_check sock, payload

                    @upstream_socket.write pack_header(payload, sock.peeraddr[1])
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
        @descriptors.delete(sock)
        sock = TCPSocket.open(sock.peeraddr[2], sock.peeraddr[1])
        @descriptors.push(sock)
    end

    def accept_new_connection
        newsock = @listen_socket.accept
        @descriptors.push(newsock)
        @ids[newsock.peeraddr[1]] = newsock
        print "accepted new connection from #{newsock.peeraddr[2]}\n" if DEBUG
    end # accept_new_connection

    def unsubscribe_connection(sock)
        sock.close
        @descriptors.delete(sock)
    end # unsubscribe_connection
end # class NSAClient

#################
# startup
#################
worker = NSAClient.new(SERVER_ADDR, SERVER_PORT, PROXY_PORT)
Signal.trap("INT") { worker.stop }
Signal.trap("TERM") { worker.stop }
worker.run
