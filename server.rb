# server.rb
# ┌───────────┬─┬────────┐
# │desc(2byte)│f│data    │
# └───────────┴─┴────────┘
# graceful close flag(0x001)が1ならば, requestキューが空の場合はコネクションをcloseしようとする
# forceful close flag(0x010)が1ならば, 強制的にコネクションclose
# response complete flag(0x100)が1ならば, requestキューから1つpopする

require "socket"
require "./request_handler"
require "./response_handler"
require "./nsa_utils"

DEBUG = true.freeze

LISTEN_PORT = 20000.freeze

class NSAServer
    include NSAUtils

    def initialize(s)
        @downstream_socket = s
        @descriptors = [@downstream_socket]
        @ids = Hash.new
        @upstream_sockets = Hash.new
        @is_tunnel = Hash.new
    end # initialize

    def run
        loop do
            s = IO::select(@descriptors)
            s[0].each do |sock|
                if sock == @downstream_socket then
                    print "Info: Received data from client\n" if DEBUG
                    # dataからidとpayloadを取り出す
                    data = sock.recv(65536)
                    if data.strip.bytesize == 0 then
                        if sock.eof? then
                            unsubscribe_connection sock
                        end
                        next
                    end
                    id, flag, payload = unpack_header(data)
                    # request処理
                    req = RequestHandler.new(payload) if @is_tunnel[sock.__id__] != :tunnel

                    # idチェック
                    if @ids[id].nil? then
                        # 新規idの場合は, 接続先ホスト, portを特定してconnection establish
                        # Request stringからhost, portを特定
                        up = TCPSocket.open(req.host, req.port)
                        @descriptors.push(up)
                        print "Established connection to origin server\n" if DEBUG
                        @upstream_sockets[id] = up
                        @ids[up.__id__] = id
                    else
                        # 既存idの場合は@idsから使用ソケットを特定
                        up = @upstream_sockets[sock.__id__]
                    end
                    # tunnel mode の場合はパススルー
                    if @is_tunnel[sock.__id__] == :tunnel then
                        up.write payload
                        next
                    end
                    if req.http_method =~ /CONNECT/i then
                        # CONNECTメソッドの場合tunnel生成
                        @is_tunnel[sock.__id__] = :tunnel
                        sock.write pack_header(
                            "HTTP/1.1 200 connection established\r\n\r\n",
                            @ids[sock.__id__]
                        )
                    else
                        # Request Stringのpath書き換え
                        p req.proxy_rewrite
                        up.write req.proxy_rewrite
                    end
                else # from Origin Server
                    print "Received response from origin server\n" if DEBUG
                    # Response Headerの書き換え
                    # idをつけてNSA Sessionを通じてClientへ流す
                    payload = sock.recv(65536)
                    if payload.strip.bytesize == 0 then
                        if sock.eof? then
                            unsubscribe_connection sock
                        end
                        next
                    end
                    res = ResponseHandler.new(payload)
                    @downstream_socket.write pack_header(res.proxy_rewrite, @ids[sock.__id__])
                    # keep aliveの有無
                end
            end # each
        end # loop
    end # run

    private

    def unsubscribe_connection(sock)
        sock.close
        @descriptors.delete(sock)
    end # unsubscribe_connection
end # class NSAWorker

# 起動
server_socket = TCPServer.open(LISTEN_PORT)
Socket.accept_loop(server_socket) do |sock|
    print "Info: Accepted new client connection from #{sock.peeraddr[2]}\n" if DEBUG
    fork do
        NSAServer.new(sock).run
    end
end
