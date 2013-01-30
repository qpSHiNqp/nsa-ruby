require "socket"
require "./nsa_utils"

class NSASession
    attr_accessor :state
    attr_accessor :sock
    attr_reader :host
    attr_reader :id

    def initialize(sock)
        @sock = sock
        peeraddr = Socket.unpack_sockaddr_in(sock.getpeername)
        @id = peeraddr[0]
        @host = peeraddr[1]
        @state = :established
    end
end

class NSAClient
    include NSAUtils

    def initialize(server_addr, server_port, listen_port)
        @sessions = Hash.new # nsa session manager
        @ids = Hash.new
        @listen_sock = TCPServer.open(listen_port)
        @up_sock = TCPSocket.open(server_addr, server_port)
        @socks = [@up_sock, @listen_sock]
    end

    def run
        loop do
            s = select(@socks)
            s[0].each do |sock|
                case sock
                when @listen_sock
                    # new connection from browser
                    accept_new_connection
                when @up_sock
                    # received from NSAServer
                    _log "Response received"
                    id, flag, data = recv(sock)
                    if flag == "\x10" then
                        server_close(id)
                    end
                    @sessions[id].sock.write(data) unless @sessions[id].nil? || data.bytesize == 0
                else
                    # received from browser
                    _log "Request Received"
                    id = @ids[sock]
                    data = sock.recv(65536)
                    if data.bytesize == 0 then
                        browser_close(id)
                    else
                        send(id, data)
                    end
                end
            end # each
        end # main loop
    end

    private

    def recv(sock)
        data = sock.recv(65536)
        if data.bytesize == 0 then
            # unbound from server; attempt to reconnect
            return
        end
        return unpack_header(data)
    end

    def send(id, data)
        @up_sock.write(pack_header(data, id))
    end

    def server_close(id)
        return if @sessions[id].nil?
        if @sessions[id].state == :half_close then
            @sessions[id].state = :closed
            destroy_session(id)
        else
            @sessions[id].state = :half_close
            @sessions[id].sock.shutdown
        end
    end

    def browser_close(id)
        return if @sessions[id].nil?
        if @sessions[id].state == :half_close then
            shutdown_session(id)
            destroy_session(id)
        else
            @sessions[id].state = :half_close
            shutdown_session(id)
        end
        @sessions[id].sock.close
        destroy_session(id)
    end

    def accept_new_connection
        _log "new connection from browser"
        ns = @listen_sock.accept
        sess = NSASession.new(ns)
        @sessions[sess.id] = sess
        @ids[ns] = sess.id
        @socks.push(ns)
    end

    def reconnect
        @up_sock.close
        @socks.delete(@up_sock)
        @up_sock = TCPSocket.open(server_addr, server_port)
        @socks.push(@up_sock)
    end

    def shutdown_session(id)
        @up_sock.write(pack_header("", id, "\x10"))
    end

    def destroy_session(id)
        @ids.delete(@sessions[id])
        @socks.delete(@sessions[id].sock)
        @sessions.delete(id)
    end
end
