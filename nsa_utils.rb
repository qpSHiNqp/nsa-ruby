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

end

def _log(msg, prefix="Info", dst=STDERR)
    dst.puts(prefix + ": " + msg)
end
