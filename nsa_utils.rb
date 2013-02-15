module NSAUtils
    def pack_header(data, id, flag="\x00")
        [id].pack("S") + flag + [data.bytesize].pack("S") + data
    end

    def unpack_header(header)
        [
            header.byteslice(0..1).unpack("S")[0],
            header.byteslice(2),
            header.byteslice(3, 2).unpack("S")[0]
        ]
    end

end

def _log(msg, prefix="Info", dst=STDERR)
    dst.puts(prefix + ": " + msg)
end
