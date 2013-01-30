require "./nsa_utils"
require "./nsa_server_session"

class NSAWorker
    include NSAUtils

    def initialize(sock)
        @down_sock = sock
        @socks = [@down_sock]
        @sessions = Hash.new
        @ids = Hash.new
    end # initialize

    def run
        s = select(@socks)
        s[0].each do |sock|
            case sock
            when @down_sock
                # received from client
                _log "Request received"
                id, flag, data = recv(sock)
                if flag == "\x10" then
                    receive_signal(id)
                end
                next if data.bytesize == 0
                if @sessions[id].nil? then
                    establish_new_session(id, data)
                end
                update_session(id, data) if @sessions[id].location_change?(data)
                @sessions[id].sock.write(@sessions[id].proxy_rewrite(data))
            else
                # received from origin
                _log "Response received"
                id = @ids[sock]
                data = sock.recv(65536)
                if data.bytesize == 0 then
                    issue_signal(id)
                else
                    send(id, @sessions[id].proxy_rewrite(data))
                end
            end
        end # each
    end # run

    private

    def establish_new_session(id, data)
        sess = NSAServerSession.new(id, data)
        @sessions[id] = sess
        @ids[sess.sock] = id
        @socks.push(sess.sock)
    end # accept_new_connection

    def update_session(id, data)
        destroy_session(id)
        establish_new_session(id, data)
    end # update_session

    def recv(sock)
        data = sock.recv(65536)
        if data.bytesize == 0 then
            return
        end
        return unpack_header(data)
    end # recv

    def send(id, data)
        @down_sock.write(pack_header(data, id))
    end # send

    def receive_signal(id)
        return if @sessions[id].nil?
        if @sessions[id].state == :half_close then
            @sessions[id].state = :closed
            destroy_session(id)
        else
            @sessions[id].state = :half_close
            @sessions[id].sock.shutdown
        end
    end # receive_signal

    def issue_signal(id)
        return if @sessions[id].nil?
        if @sessions[id].state == :half_close then
            shutdown_session(id)
            destroy_session(id)
        else
            @sessions[id].state = :half_close
            shutdown_session(id)
        end
        @sessions[id].sock.close
    end # issue signal

    def shutdown_session(id)
        @down_sock.write(pack_header("", id, "\x10"))
    end

    def destroy_session(id)
        @ids.delete(@sessions[id].sock)
        @socks.delete(@sessions[id].sock)
        @sessions.delete(id)
    end
end # class NSAWorker
