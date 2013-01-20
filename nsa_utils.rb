module NSAUtils
    def unpack_header(data)
        data.byteslice(0, 2).unpack("H*").to_s.hex.to_i, data.byteslice(2, 1), data.byteslice(3, data.bytesize - 3)
    end

    def pack_header(data, id, flag="\x00")
        [id.to_s(16)].pack("H*") + flag + data
    end
end
