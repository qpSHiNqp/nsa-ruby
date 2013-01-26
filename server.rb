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
        @ids = Hash.new # upstram_socketからidを引く
        @upstream_sockets = Hash.new # idからupstream_socketを引く
        @is_tunnel = Hash.new # idからconnection modeを引く
    end # initialize

    def run
        loop do
            s = IO::select(@descriptors)
            s[0].each do |sock|
                case sock
                when @downstream_socket
                    _log "Received data from client\n"
                    # dataからidとpayloadを取り出す
                    data = sock.recv(65536)

                    if data.length == 0 then
                        # disconnected. termination process
                        self.stop
                        next
                    end

                    id, flag, payload = unpack_header(data)
                    if flag == "\x10" then
                        unsubscribe_connection(@upstream_sockets[id][0], true) unless @upstream_sockets[id].nil?
                        next if payload.bytesize == 0
                    end

                    if @is_tunnel[id] == :tunnel then
                        @upstream_sockets[id][0].write payload
                        next
                    end

                    # request処理
                    req = RequestHandler.new(payload)
                    # idチェック
                    if @upstream_sockets[id].nil? then
                        # 新規idの場合は, 接続先ホスト, portを特定してconnection establish
                        # Request stringからhost, portを特定
                        up = TCPSocket.open(req.host, req.port)
                        @descriptors.push(up)
                        _log "Established connection to origin server\n"
                        @upstream_sockets[id] = [up, req.host, req.port]
                        @ids[up.__id__] = id
                    end
                    # 既存idの場合は@idsから使用ソケットを特定
                    upstream_info = @upstream_sockets[id]
                    up = upstream_info[0]

                    # Request Stringのpath書き換え
                    if upstream_info[1] != req.host || upstream_info[2] != req.port then
                        @descriptors.delete(up)
                        @ids.delete(up.__id__)
                        @upstream_sockets.delete(id)
                        up.close
                        up = TCPSocket.open(req.host, req.port)
                        @descriptors.push(up)
                        @ids[up.__id__] = id
                        @upstream_sockets[id] = [up, req.host, req.port]
                    end

                    if req.http_method =~ /CONNECT/i then
                        # CONNECTメソッドの場合tunnel生成
                        @is_tunnel[id] = :tunnel
                        sock.write pack_header(
                            "HTTP/1.1 200 connection established\r\n\r\n", id)
                        next
                    end

                    #p req.proxy_rewrite
                    up.write req.proxy_rewrite

                else # from Origin Server
                    _log "Received response from origin server\n"
                    payload = sock.recv(65536)
                    if payload.length == 0 then
                        unsubscribe_connection sock
                        next
                    end
                    res = ResponseHandler.new(payload)
                    @downstream_socket.write pack_header(res.proxy_rewrite, @ids[sock.__id__])
                end
            end # each
        end # loop
    end # run

    def stop
        @descriptors.each do |s|
            begin
                s.shutdown
            rescue Errno::ENOTCONN
                @descriptors.delete(s)
                s.close
            end
        end
    end # stop

    private

    def unsubscribe_connection(sock, shutdown=false)
        if shutdown then
            sock.shutdown
        else
            @descriptors.delete(sock)
            if sock == @downstream_socket then
                @descriptors.each do |s|
                    s.shutdown
                end
                @descriptors.delete(sock)
                @downstream_socket = nil
            else
                id = @ids[sock.__id__]
                @ids.delete(sock.__id__)
                @is_tunnel.delete(id)
                @upstream_sockets.delete(id)
                # shutdown signalを送信
                @downstream_socket.write(pack_header("", id, "\x10")) unless @downstream_socket.nil?
            end
            sock.close
        end
        exit if @descriptors.length == 0
    end # unsubscribe_connection
end # class NSAWorker

###################
# 起動
###################
processes = Array.new
Signal.trap("INT") do
    processes.each do |p|
        Process.kill "INT", p
    end
end
Signal.trap("TERM") do
    processes.each do |p|
        Process.kill "TERM", p
    end
end
server_socket = TCPServer.open(LISTEN_PORT)
Socket.accept_loop(server_socket) do |sock|
    _log "Accepted new client connection from #{sock.peeraddr[2]}\n"
    pid = fork do
        worker = NSAServer.new(sock)
        Signal.trap("INT") { worker.stop }
        Signal.trap("TERM") { worker.stop }
        worker.run
    end
    processes.push(pid)
end
