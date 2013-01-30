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
        @state = Hash.new
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
                        _log "Downstream connection lost\n"
                        self.stop
                        next
                    end

                    id, flag, payload = unpack_header(data)
                    if flag == "\x10" then
                        graceful_close(@upstream_sockets[id][0]) unless @upstream_sockets[id].nil?
                    end

                    if @is_tunnel[id] == :tunnel then
                        @upstream_sockets[id][0].write payload
                        next
                    end
                    next if payload.bytesize == 0

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
                    begin
                        payload = sock.recv(65536)
                    rescue Errno::ECONNRESET
                        unsubscribe_connection sock
                    end
                    if payload.length == 0 then
                        _log "Closed connection to origin server: #{sock}\n"
                        unsubscribe_connection sock
                        next
                    end

                    id = @ids[sock.__id__]
                    if @is_tunnel[id] == :tunnel then
                        @downstream_socket.write pack_header(payload, id)
                        next
                    end
                    res = ResponseHandler.new(payload)
                    @downstream_socket.write pack_header(res.proxy_rewrite, id)
                end
            end # each
        end # loop
    end # run

    def stop
        @descriptors.each do |s|
            begin
                s.shutdown
            rescue Errno::ENOTCONN
                _log "socket #{s} already disconnected"
                @descriptors.delete(s)
                s.close
            end
        end
    end # stop

    private

    def graceful_close(sock)
        if sock then
            _log "Shutdown connection: #{@ids[sock.__id__]}\n"
            id = @ids[sock.__id__]
            if @state[id] == :half_close then
                @state.delete(id)
            else
                begin
                    sock.shutdown
                rescue Errno::ENOTCONN
                    _log "socket #{sock} already disconnected"
                    @descriptors.delete(sock)
                    sock.close
                end
                @state[id] = :half_close
            end
        end
    end

    def unsubscribe_connection(sock)
        @descriptors.delete(sock)
        if sock == @downstream_socket then
            @descriptors.each do |s|
                s.shutdown
            end
            @descriptors.delete(sock)
            @downstream_socket = nil
        else
            id = @ids[sock.__id__]
            _log "Closing connection: #{id}\n"
            if @state[id] == :half_close then
                @state.delete(id)
            else
                @state[id] = :half_close
            end
            @downstream_socket.write(pack_header("", id, "\x10")) unless @downstream_socket.nil?
            @ids.delete(sock.__id__)
            @is_tunnel.delete(id)
            @upstream_sockets.delete(id)
            # shutdown signalを送信
        end
        sock.close
        exit if @descriptors.length == 0
    end # unsubscribe_connection
end # class NSAWorker

###################
# 起動
###################
processes = Array.new
#Signal.trap("INT") do
#    processes.each do |p|
#        Process.kill "INT", p
#    end
#end
#Signal.trap("TERM") do
#    processes.each do |p|
#        Process.kill "TERM", p
#    end
#end
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
