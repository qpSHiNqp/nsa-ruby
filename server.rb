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
            s = select(@descriptors)
            s[0].each do |sock|
                if sock == @downstream_socket then
                    # dataからidとpayloadを取り出す
                    id, flag, payload = unpack_header(sock.recv(65536))
                    # request処理
                    req = RequestHandler.new(payload)

                    # idチェック
                    if @ids[sock.object_id].nil? then
                        # 新規idの場合は, 接続先ホスト, portを特定してconnection establish
                        # Request stringからhost, portを特定
                        up = TCPConnection.open(req.host, req.port)
                        @upstream_sockets[sock.object_id] = up
                        @ids[sock.object_id] = id
                    else
                        # 既存idの場合は@idsから使用ソケットを特定
                        up = @upstream_sockets[sock.object_id]
                    end
                    if req.method =~ /CONNECT/i then
                        # CONNECTメソッドの場合tunnel生成
                        @is_tunnel[sock.object_id] = :tunnel
                        sock.write "HTTP/1.1 200 connection established\r\n\r\n"
                    else
                        # それ以外の場合
                        # tunnel mode の場合はパススルー
                        if @is_tunnel[sock.object_id] == :tunnel then
                            up.write payload
                        else
                            # Request Stringのpath書き換え
                            payload = req.proxy_rewrite
                            up.write payload
                        end
                    end
                else # from Origin Server
                    begin
                        # Response Headerの書き換え
                        # idをつけてNSA Sessionを通じてClientへ流す
                        @upstream_socket.write pack_header(sock.recv(65536), @ids[sock.object_id])
                        # keep aliveの有無
                    rescue
                        if sock.eof? then
                            sock.close
                            @descriptors.delete(sock)
                        end
                    end
                end
            end # each
        end # loop
    end # run
end # class NSAWorker

# 起動
server_socket = TCPServer.open(LISTEN_PORT)
accept_loop(server_socket) do |sock|
    fork do
        NSAServer.new(sock).run
    end
end
