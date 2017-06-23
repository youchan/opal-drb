require 'native'
require 'promise'

class ArrayBuffer
  include Native

  native_reader :buffer
  native_reader :length

  def to_s
    result = ""
    arr = []
    %x(
      for (var i = 0; i < self.native.length; i ++) {
        arr.push(self.native[i]);
        result += String.fromCharCode(self.native[i]);
      }
    )
    result
  end
end

class WebSocket
  include Native

  def initialize(url)
    super `new WebSocket(url)`
    `self.native.binaryType = 'arraybuffer'`
  end

  def onmessage
    add_event_listener('message') {|event| yield MessageEvent.new(event) }
  end

  def onopen
    add_event_listener('open') {|event| yield MessageEvent.new(event) }
  end

  alias_native :close
  alias_native :send
  alias_native :add_event_listener, :addEventListener

  class MessageEvent
    include Native

    def data
      ArrayBuffer.new(`new Uint8Array(self.native.data)`)
    end
  end
end

module DRb
  module WebSocket
    class StrStream
      def initialize(str='')
        @buf = str
      end
      attr_reader :buf

      def read(n)
        begin
          return @buf[0,n]
        ensure
          @buf = @buf[n, @buf.size - n]
        end
      end

      def write(s)
        @buf += s
      end
    end

    def self.uri_option(uri, config)
      return uri, nil
    end

    def self.open(uri, config)
      unless uri =~ /^ws:\/\/(.*?):(\d+)(\?(.*))?$/
        raise(DRbBadScheme, uri) unless uri =~ /^ws:/
        raise(DRbBadURI, 'can\'t parse uri:' + uri)
      end
      ClientSide.new(uri, config)
    end

    class ClientSide
      def initialize(uri, config)
        @uri = uri
        @res = nil
        @config = config
        @msg = DRbMessage.new(config)
        @proxy = ENV['HTTP_PROXY']
      end

      def close
      end

      def alive?
        false
      end

      def send_request(ref, msg_id, *arg, &b)
        stream = StrStream.new
        @msg.send_request(stream, ref, msg_id, *arg, &b)
        post(@uri, stream.buf)
      end

      def recv_reply(reply_stream)
        @ws.close
        @msg.recv_reply(reply_stream)
      end

      def post(uri, data)
        promise = Promise.new
        @ws = ::WebSocket.new(uri)
        @ws.onmessage do |event|
          reply_stream = StrStream.new
          reply_stream.write(event.data.to_s)

          if @config[:load_limit] < reply_stream.buf.size
            raise TypeError, 'too large packet'
          end

          promise.resolve reply_stream
        end

        @ws.onopen do
          @ws.send(`new Uint8Array(#{data.bytes.each_slice(2).map(&:first)}).buffer`)
        end
        promise
      end
    end
  end
end

