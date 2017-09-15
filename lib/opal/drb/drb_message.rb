module DRb
  class DRbMessage
    def initialize(config)
      config = DRb.default_config.merge(config || {})
      @load_limit = config[:load_limit]
      @argc_limit = config[:argc_limit]
    end

    def dump(obj, error=false)
      obj = make_proxy(obj, error) if obj.kind_of? DRbUndumped
      begin
        str = Marshal::dump(obj)
      rescue
        str = Marshal::dump(make_proxy(obj, error))
      end
      pack_n(str.size) + str
    end

    def load(soc)
      begin
        sz = soc.read(4)
      rescue
        raise(DRbConnError, $!.message, $!.backtrace)
      end

      raise(DRbConnError, 'connection closed') if sz.nil?
      raise(DRbConnError, 'premature header') if sz.size < 4

      sz = unpack_n(sz)[0]

      raise(DRbConnError, "too large packet #{sz}") if @load_limit < sz
      begin
        str = soc.read(sz)
      rescue
        raise(DRbConnError, $!.message, $!.backtrace)
      end

      raise(DRbConnError, 'connection closed') if str.nil?
      raise(DRbConnError, 'premature marshal format(can\'t read)') if str.size < sz

      Marshal::load(str)
    end

    def send_request(stream, ref, msg_id, arg, b)
      ary = []
      ary.push(dump(ref.__drbref))
      ary.push(dump(msg_id))
      ary.push(dump(arg.length))
      arg.each do |e|
        ary.push(dump(e))
      end
      ary.push(dump(b))
      stream.write(ary.join(''))
    rescue
      raise(DRbConnError, $!.message, $!.backtrace)
    end

    def recv_request(stream)
      ref = load(stream)
      ro = DRb.to_obj(ref)
      msg = load(stream)
      argc = load(stream)
      raise(DRbConnError, "too many arguments") if @argc_limit < argc
      argv = Array.new(argc, nil)
      argc.times do |n|
        argv[n] = load(stream)
      end
      block = load(stream)
      return ro, msg, argv, block
    end

    def send_reply(stream, succ, result)
      stream.write(dump(succ) + dump(result, !succ))
    rescue
      raise(DRbConnError, $!.message, $!.backtrace)
    end

    def recv_reply(stream)
      succ = load(stream)
      result = load(stream)
      [succ, result]
    end

    private
    def make_proxy(obj, error=false)
      if error
        DRbRemoteError.new(obj)
      else
        DRbObject.new(obj)
      end
    end

    def pack_n(n)
      %x{
        var s = "";
        for (var i = 0; i < 4; i++) {
          var b = n & 255;
          s = String.fromCharCode(b) + s;
          n >>= 8
        }

        return s;
      }
    end

    def unpack_n(s)
      s.bytes.each_slice(2).map(&:first).each_slice(4).map do |x|
        x[0] << 24 | x[1] << 16 | x[2] << 8 | x[3]
      end
    end
  end
end
