module DRb
  class DRbServer
    attr_reader :uri

    def initialize(uri)
      @uri = uri
      @protocol = DRbProtocol.open_server(@uri)
      run
    end

    def run
      @protocol.accept do |client|
        begin
          succ = false
          invoke_method = InvokeMethod.new(self, client)
          succ, result = invoke_method.perform
          print_error(result) unless succ
          client.send_reply(succ, result)
        rescue Exception => e
          print_error(e)
        ensure
          client.close unless succ
          break unless succ
        end
      end
    end

    def print_error(e)
      puts e.message
      p e.backtrace
    end
  end
end
