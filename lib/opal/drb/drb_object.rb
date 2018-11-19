module DRb
  class DRbObject
    def self._load(s)
      uri, ref = Marshal.load(s)
      self.new_with(uri, ref)
    rescue Exception => e
      `console.log(e)`
    end

    def self.new_with(uri, ref)
      it = self.allocate
      it.instance_variable_set(:@uri, uri)
      it.instance_variable_set(:@ref, ref)
      it
    end

    def self.new_with_uri(uri)
      self.new(nil, uri)
    end

    def _dump(lv)
      Marshal.dump([@uri, @ref])
    end

    def initialize(obj, uri=nil)
      @uri = nil
      @ref = nil
      if obj.nil?
        return if uri.nil?
        @uri, option = DRbProtocol.uri_option(uri, DRb::default_config)
        @ref = DRbURIOption.new(option) unless option.nil?
      else
        @uri = uri ? uri : DRb.current_server.uri
        @ref = obj ? DRb.to_id(obj) : nil
        DRbObject.id2ref[@ref] = obj
      end
    end

    def __drburi
      @uri
    end

    def __drbref
      @ref
    end

    def self.id2ref
      @id2ref ||= {}
    end

    def inspect
      @ref && @ref.inspect
    end

    def respond_to?(msg_id, priv=false)
      case msg_id
      when :_dump
        true
      when :marshal_dump
        false
      else
        false
      end
    end

    def method_missing(msg_id, *a, &b)
      promise = Promise.new
      DRbConn.open(@uri) do |conn|
        conn.send_message(self, msg_id, a, b) do |succ, result|
          if succ
            promise.resolve result
          elsif DRbUnknown === result
            promise.resolve result
          else
            bt = self.class.prepare_backtrace(@uri, result)
            result.set_backtrace(bt + caller)
            promise.resolve result
          end
        end
      end
      promise
    end

    def self.prepare_backtrace(uri, result)
      prefix = "(#{uri}) "
      bt = []
      result.backtrace.each do |x|
        break if /`__send__'$/ =~ x
        if /^\(druby:\/\// =~ x
          bt.push(x)
        else
          bt.push(prefix + x)
        end
      end
      bt
    end

    def pretty_print(q)
      q.pp_object(self)
    end

    def pretty_print_cycle(q)
      q.object_address_group(self) {
        q.breakable
        q.text '...'
      }
    end
  end
end
