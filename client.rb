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
        @listen_socket = TCPServer.open(listen_port)
        @descriptors = [@upstream_socket, @listen_socket]
        @ids = Hash.new
    end # initialize

    def run
        loop do
            s = select(@descriptors)
            s[0].each do |sock|
                if sock == @listen_socket then # 新しい接続要求
                    accept_new_connection
                elsif sock == @upstream_socket then # NSAServerからのresponse
                    id, flag, payload = unpack_header(sock.recv(65536))
                    @ids[id].write(payload)
                else # Browserからのrequest
                    begin
                        # session id は接続元port番号
                        @upstream_socket.write pack_header(sock.recv(65536), @ids[sock.peeraddr[1]])
                    rescue
                        if sock.eof? then
                            # disconnected. some procedure
                            sock.close
                            @descriptors.delete(sock)
                        end
                    end
                end
            end # each
        end # loop
    end # run

    private

    def accept_new_connection
        newsock = @listen_socket.accept
        @descriptors.push(newsock)
        @ids[newsock.peeraddr[1]] = newsock
    end # accept_new_connection
end # class NSAClient

nsa_client = NSAClient.new(SERVER_ADDR, SERVER_PORT, PROXY_PORT)
nsa_client.run
