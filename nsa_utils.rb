module NSAUtils
    def pack_header(data, id, flag="\x00")
        [id].pack("S") + flag + data
    end

    def unpack_header(data)
        [
            data.byteslice(0..1).unpack("S")[0],
            data.byteslice(2),
            data.byteslice(3, data.bytesize - 3)
        ]
    end

    def alive_check (sock, data)
        if sock.eof? then
            unsubscribe_connection sock
            return false
        end
        return false if data.bytesize == 0
        return true
    end
end
