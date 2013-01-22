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
                if sock == @listen_socket then # 新しい接続要求
                    accept_new_connection
                elsif sock == @upstream_socket then # NSAServerからのresponse
                    id, flag, payload = unpack_header(sock.recv(65536))
                    @ids[id].write(payload)
                else # Browserからのrequest
                    print "Info: Received data from browser\n" if DEBUG
                    payload = ""
                    begin
                        # session id は接続元port番号
                        payload = sock.recv(65536)
                    rescue
                        print "Info: Recv failed\n" if DEBUG
                        if sock.eof? then
                            # disconnected. some procedure
                            unsubscribe_connection sock
                            next
                        end
                    end
                    if payload.strip.bytesize == 0 then
                        if sock.eof? then
                            unsubscribe_connection sock
                        end
                        next
                    end

                    @upstream_socket.write pack_header(payload, sock.peeraddr[1])
                end
            end # each
        end # loop
    end # run

    private

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

NSAClient.new(SERVER_ADDR, SERVER_PORT, PROXY_PORT).run
