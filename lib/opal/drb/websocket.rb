require 'native'
require 'promise'
require 'securerandom'

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
    @listeners = {}
  end

  def onmessage(&block)
    listener = Proc.new {|event| yield MessageEvent.new(event) if self.open? }
    @listeners[block] = [:message, listener]
    add_event_listener('message', &listener)
  end

  def onopen(&block)
    listener = Proc.new {|event| yield Native(event) }
    @listeners[block] = [:open, listener]
    add_event_listener('open', &listener)
  end

  def onclose(&block)
    listener = Proc.new {|event| yield Native(event) }
    @listeners[block] = [:close, listener]
    add_event_listener('close', &listener)
  end

  def off handler
    remove_event_listener(*@listeners[handler])
  end

  def connecting?
    `#@native.readyState === 0`
  end

  def open?
    `#@native.readyState === 1`
  end

  def closing?
    `#@native.readyState === 2`
  end

  def closed?
    `#@native.readyState === 3`
  end

  alias_native :close
  alias_native :send
  alias_native :add_event_listener, :addEventListener
  alias_native :remove_event_listener, :removeEventListener

  class MessageEvent
    include Native

    def data
      ArrayBuffer.new(`new Uint8Array(self.native.data)`)
    end
  end
end

module DRb
  module WebSocket
    class SocketPool
      def initialize
        @sockets = {}
        @proxy = ENV['HTTP_PROXY']
      end

      def open(uri)
        @sockets[uri] ||= ::WebSocket.new(uri)
      end

      alias_method :[], :open
    end
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
      @pool ||= SocketPool.new
      unless uri =~ /^ws:\/\/(.*?):(\d+)(\/(.*))?$/
        raise(DRbBadScheme, uri) unless uri =~ /^ws:/
        raise(DRbBadURI, 'can\'t parse uri:' + uri)
      end
      ClientSide.new(uri, @pool[uri], config)
    end

    def self.open_server(uri, config)
      unless uri =~ /^ws:\/\/(.*?):(\d+)(\/(.*))?$/
        raise(DRbBadScheme, uri) unless uri =~ /^ws:/
        raise(DRbBadURI, 'can\'t parse uri:' + uri)
      end

      Server.new(uri, config)
    end

    class Server
      attr_reader :uri

      def initialize(uri, config)
        @uri = "#{uri}/#{SecureRandom.uuid}"
        @config = config
      end

      def close
        @ws.close
      end

      def accept
        ws = ::WebSocket.new(@uri)
        ws.onmessage do |event|
          stream = StrStream.new(event.data.to_s)
          server_side = ServerSide.new(stream, @config, uri)
          yield server_side
          ws.send(`new Uint8Array(#{server_side.reply.bytes.each_slice(2).map(&:first)}).buffer`)
        end
      end
    end

    class ServerSide
      attr_reader :uri, :reply

      def initialize(stream, config, uri)
        @uri = uri
        @config = config
        @msg = DRbMessage.new(@config)
        @req_stream = stream
        @sender_id = SecureRandom.uuid
      end

      def close
      end

      def alive?; false; end

      def recv_request
        begin
          @msg.recv_request(@req_stream)
        rescue
          close
          raise $!
        end
      end

      def send_reply(succ, result)
        begin
          stream = StrStream.new
          @msg.send_reply(stream, succ, result)
          @reply = stream.buf
        rescue
          close
          raise $!
        end
      end
    end

    class ClientSide
      def initialize(uri, ws, config)
        @uri = uri
        @ws = ws
        @res = nil
        @config = config
        @msg = DRbMessage.new(@config)
        @sender_id = SecureRandom.uuid
      end

      def alive?
        !!@ws && @ws.open?
      end

      def close
        @ws = nil
      end

      def send_request(ref, msg_id, *arg, &b)
        stream = StrStream.new
        @msg.send_request(stream, ref, msg_id, *arg, &b)
        send(@uri, stream.buf)
      end

      def recv_reply(reply_stream)
        @msg.recv_reply(reply_stream)
      end

      def send(uri, data)
        promise = Promise.new
        event_handler = Proc.new do |event|
          message_data = event.data.to_s
          sender_id = message_data.slice(0, 36)
          message = message_data.slice(36, message_data.length - 36)

          unless sender_id == @sender_id
            next
          end

          reply_stream = StrStream.new
          reply_stream.write(message.to_s)

          if @config[:load_limit] < reply_stream.buf.size
            raise TypeError, 'too large packet'
          end

          promise.resolve reply_stream
          @ws.off(event_handler)
        end
        @ws.onmessage &event_handler
        byte_data = @sender_id.bytes.each_slice(2).map(&:first)
        byte_data += data.bytes.each_slice(2).map(&:first)

        if @ws.connecting?
          @ws.onopen do
            @ws.send(`new Uint8Array(#{byte_data}).buffer`)
          end
        else
          @ws.send(`new Uint8Array(#{byte_data}).buffer`)
        end

        promise
      end
    end
  end
end

