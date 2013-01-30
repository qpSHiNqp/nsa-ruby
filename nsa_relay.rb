class NSARelay
    attr_accessor :state
    attr_accessor :sock
    attr_reader :host
    attr_reader :id
    def initialize(sock)
        @sock = sock
        @id = sock.peeraddr[1]
        @host = sock.peeraddr[2]
        @state = :established
    end
end
