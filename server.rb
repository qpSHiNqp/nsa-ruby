# server.rb
# ┌───────────┬─┬────────┐
# │desc(2byte)│f│data    │
# └───────────┴─┴────────┘
# graceful close flag(0x001)が1ならば, requestキューが空の場合はコネクションをcloseしようとする
# forceful close flag(0x010)が1ならば, 強制的にコネクションclose
# response complete flag(0x100)が1ならば, requestキューから1つpopする

require "socket"
require "./request_handler"

LISTEN_PORT = 20000.freeze

class NSAWorker
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
                    # dataからidとpayloadを取り出す
                    data = sock.recv(65536)
                    id = data.byteslice(0, 2).to_i
                    payload = data.byteslice(3, data.bytesize - 3)

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
                        @upstream_socket.write @ids[sock.object_id] + "\x00" + sock.recv(65536)

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

class NSAServer
    def initialize(listen_port)
        @server_socket = TCPServer.open(listen_port)
        @descriptors = [@server_socket]
    end # initialize

    def run
        loop do
            #s = IO::select(@descriptors)
            #s[0].each do |sock|
            #    if sock == @server_socket then
            #        accept_new_connection
            #    end
            #end # each
            accept_loop(@server_socket) do |sock|
                fork do
                    NSAWorker.new(sock).run
            end
        end # loop
    end

    #private

    #def accept_new_connection
    #    newsock = @server_socket.accept
    #    #@descriptors.push(newsock)
    #    fork do
    #        worker = NSAWorker.new(newsock)
    #        worker.run
    #    end
    #end # accept_new_connection
end # NSAServer

server = NSAServer.new(LISTEN_PORT)
server.run
