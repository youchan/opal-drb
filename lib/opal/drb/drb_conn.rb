module DRb
  class DRbConn
    POOL_SIZE = 16
    @pool = []

    def self.open(remote_uri)
      begin
        conn = nil

        @pool = @pool.each_with_object([]) do |c, new_pool|
          if conn.nil? and c.uri == remote_uri
            conn = c if c.alive?
          else
            new_pool.push c
          end
        end

        conn = self.new(remote_uri) unless conn
        succ, result = yield(conn)
        return succ, result

      ensure
        if conn
          if succ
            @pool.unshift(conn)
            @pool.pop.close while @pool.size > POOL_SIZE
          else
            conn.close
          end
        end
      end
    end

    def initialize(remote_uri)
      @uri = remote_uri
      @protocol = DRbProtocol.open(remote_uri, DRb::default_config)
    end
    attr_reader :uri

    def send_message(ref, msg_id, arg, b, &callback)
      @protocol.send_request(ref, msg_id, arg, b).then do |stream|
        callback.call(@protocol.recv_reply(stream))
      end
    end

    def close
      @protocol.close
      @protocol = nil
    end

    def alive?
      return false unless @protocol
      @protocol.alive?
    end
  end
end
