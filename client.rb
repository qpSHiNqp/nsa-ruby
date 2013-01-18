# client.rb
# 起動したら, nsa sessionを確立する
# ブラウザ接続のためのlisten
# ブラウザの接続がアレばacceptとfork
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
# establish flag(0x1000)が1ならば, 新規セッションであることをserverへ通知

require "socket"

SERVER_ADDR = "127.0.0.1".freeze
SERVER_PORT = 20000.freeze
PROXY_PORT = 8080.freeze

class NSAClient
    def initialize(server_addr, server_port, listen_port)
        @upstream_socket = TCPSocket.open(server_addr, server_port)
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
                    # そのままchild processに渡す
                    data = sock.recv
                    @ids[data.byteslice(0,2).to_i].write(data)
                else # Browserからのrequest
                    if sock.eof? then
                        # disconnected. some procedure
                        sock.close
                        @descriptors.delete(sock)
                    else
                        # session id は接続元port番号
                        @upstream_socket.write sock.peeraddr[2] + "\x00" + sock.recv
                    end
                end
            end # each
        end # loop
    end # run

    private

    def accept_new_connection
        newsock, sockaddr = @listen_socket.accept
        @descriptors.push(newsock)
        @ids[newsock.peeraddr[2] = newsock
    end # accept_new_connection
end # class NSAClient

nsa_client = NSAClient.new(SERVER_ADDR, SERVER_PORT, PROXY_PORT)
nsa_client.run

#pipes = {}
#
#sock_up = TCPSocket.open(SERVER_ADDR, SERVER_PORT)
#
#sock_listen = TCPServer.open(PROXY_PORT)
#
#socks = [sock_up, sock_listen]
#
#loop do
#    s = IO::select(socks)
#    s[0].each do |sock|
#        if sock === sock_listen then
#            # connection request. fork child process
#            client = sock_listen.accept
#            c_out, s_in = IO.pipe
#            s_out, c_in = IO.pipe
#            socks.push(s_out)
#
#            pid = fork do
#                client_id = pid
#                s = IO::select([c_out, client])
#                s[0].each do |sock|
#                    if sock === client then
#                        # ブラウザからのwriteは, session descriptorとflag byteを付加してserverへ送信
#                        data = sock.recv
#                        data = client_id.to_s + "\x00" + data
#                        sock_up.write(data)
#                    else
#                        # pipeに対するIOは, descriptorとflag byteを取り除いてブラウザへ送信
#                        data = sock.recv
#                        data = data.byteslice(3, data.bytesize - 3)
#                        client.write(data)
#                    end
#                end
#            end
#            pipes[pid] = [s_in, s_out]
#
#        elsif sock === sock_up then
#            # descriptorを解析して, そのdescriptorで示されるs_inにdataを書き込む.
#            payload = sock.recv
#            desc = payload.byteslice(0, 2)
#            desc = desc.to_i
#            pipes[desc][0].write(payload)
#            # flagによってはprocessをkillし, pipeを破棄する
#        else
#            # そのままserverへpayloadをパスする
#            sock_up.write sock.recv
#        end
#    end
#end
#
#sock_listen.close
#sock_up.close
