# server.rb
# 起動したら, nsa session用ソケットをlisten
# clientの接続がアレばacceptとfork
# 1. master process
#   ソケットをselect
#   書き込みがあったソケットが子プロセスとのpipeだった場合は, データにdescriptor番号を付加してnsa-serverへ送信
#   書き込みソケットがnsa-serverとのコネクションだった場合は, descriptor番号を調べて適切な子プロセスのpipeへ書き込み
# 2. child process
#   ソケットをselect
#   書き込みがあったソケットが
#
# ┌───────────┬─┬────────┐
# │desc(2byte)│f│data    │
# └───────────┴─┴────────┘
# graceful close flag(0x001)が1ならば, requestキューが空の場合はコネクションをcloseしようとする
# forceful close flag(0x010)が1ならば, 強制的にコネクションclose
# response complete flag(0x100)が1ならば, requestキューから1つpopする

require "socket"

LISTEN_PORT = 20000.freeze

class NSAWorker
    def initialize(s)
        @downstream_socket = s
        @descriptors = [@downstream_socket]
        @ids = Hash.new
    end # initialize

    def run
        loop do
            s = IO::select(@descriptors)
            s[0].each do |sock|
                if sock == @downstream_socket then
                    # idチェック
                    #   - 既存idの場合は@idsから使用ソケットを特定
                    #   - 新規idの場合は, Request Stringから接続先ホスト, portを特定してconnection establish
                    # CONNECTメソッドの場合
                    #   - tunnel生成
                    # それ以外の場合
                    #   - Request Headerの書き換え
                    #   - Request Stringのpath書き換え
                    #   - 送信
                else # from Origin Server
                    if sock.eof? then
                        sock.close
                        @descriptors.delete(sock)
                    else
                        # Response Headerの書き換え
                        # idをつけてNSA Sessionを通じてClientへ流す
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
            s = IO::select(@descriptors)
            s[0].each do |sock|
                if sock == @server_socket then
                    accept_new_connection
                end
            end # each
        end # loop
    end

    private

    def accept_new_connection
        newsock = @server_socket.accept
        #@descriptors.push(newsock)
        fork do
            worker = NSAWorker.new(newsock)
            worker.run
        end
    end # accept_new_connection
end # NSAServer

server = NSAServer.new(LISTEN_PORT)
server.run

#loop do
#    s = IO::select(socks)
#    s[0].each do |sock|
#        if sock === sock_listen then
#            # connection request. fork child process
#            client = sock_listen.accept
#
#            fork do
#                sock_client = client
#                socks = [client]
#                s = IO::select(socks)
#                pipes = {}
#                s[0].each do |sock|
#                    if sock === sock_client then
#                        # clientからのwriteは, session descriptorとflag byteをチェックしてworkerへ送信
#                        data = sock.recv
#                        desc = data.byteslice(0, 2)
#                        desc = desc.to_i
#                        begin
#                            pipes[desc][0].write(data)
#                        rescue
#                            # 対応するworkerが無いので生成
#                            w_out, m_in = IO.pipe
#                            m_out, w_in = IO.pipe
#                            socks.push(m_out)
#                            fork do
#                            end
#                        end
#                    else
#                        # pipeに対するIOはそのままclientに送信
#                        sock_client.write sock.recv
#                    end
#                end
#            end
#            pipes[pid] = [s_in, s_out]
#
#        elsif sock === sock_up then
#            # descriptorを解析して, そのdescriptorで示されるs_inにdataを書き込む.
#            data = sock.recv
#            desc = data.byteslice(0, 2)
#            desc = desc.to_i
#            pipes[desc][0].write(data)
#            # flagによってはprocessをkillし, pipeを破棄する
#        else
#            # そのままserverへpayloadをパスする
#            sock_up.write sock.recv
#        end
#    end
#    client = sock_listen.accept
#    fork do
#
#    end
#end
#
#sock.close
#
#sock_listen.close
