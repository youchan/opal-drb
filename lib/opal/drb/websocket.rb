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
      attr_reader :uri, :ws

      def initialize(uri, ws)
        @uri = uri
        @ws = ws
        @handlers = {}

        ws.onmessage do |event|
          message_data = event.data.to_s
          sender_id = message_data.slice(0, 36)
          message = message_data.slice(36, message_data.length - 36)
          @handlers.delete(sender_id).call(message)
        end
      end

      def self.open(uri)
        @sockets ||= {}
        @sockets[uri] ||= new_connection(uri)
      end

      def self.new_connection(uri)
        ws = ::WebSocket.new(uri)

        ws.onclose do
          @sockets[uri] = new_connection(uri)
        end

        self.new(uri, ws)
      end

      def send(data, &block)
        sender_id = SecureRandom.uuid
        @handlers[sender_id] = block
        byte_data = sender_id.bytes.each_slice(2).map(&:first)
        byte_data += data.bytes.each_slice(2).map(&:first)

        if @ws.connecting?
          @ws.onopen do
            @ws.send(`new Uint8Array(#{byte_data}).buffer`)
          end
        else
          @ws.send(`new Uint8Array(#{byte_data}).buffer`)
        end
      end

      def [](uri)
        @sockets[uri].ws
      end
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
      unless uri =~ /^ws:\/\/(.*?):(\d+)(\/(.*))?$/
        raise(DRbBadScheme, uri) unless uri =~ /^ws:/
        raise(DRbBadURI, 'can\'t parse uri:' + uri)
      end
      ClientSide.new(uri, config)
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
        reconnect
      end

      def close
        @ws.close
      end

      def reconnect
        @ws.close if @ws

        @ws = ::WebSocket.new(@uri)

        @ws.onclose do |event|
          reconnect
        end

        @ws.onmessage do |event|
          message_data = event.data.to_s
          sender_id = message_data.slice(0, 36)
          message = message_data.slice(36, message_data.length - 36)
          stream = StrStream.new(message)
          server_side = ServerSide.new(stream, @config, uri)
          @accepter.call server_side

          send_data = sender_id.bytes.each_slice(2).map(&:first)
          send_data += server_side.reply.bytes.each_slice(2).map(&:first)
          @ws.send(`new Uint8Array(#{send_data}).buffer`)
        end
      end

      def accept(&block)
        @accepter = block
      end
    end

    class ServerSide
      attr_reader :uri, :reply

      def initialize(stream, config, uri)
        @uri = uri
        @config = config
        @msg = DRbMessage.new(@config)
        @req_stream = stream
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
      def initialize(uri, config)
        @uri = uri
        @pool =  SocketPool.open(uri)
        @res = nil
        @config = config
        @msg = DRbMessage.new(@config)
      end

      def alive?
        !!@pool.ws && @pool.ws.open?
      end

      def close
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
        @pool.send(data) do |message|
          reply_stream = StrStream.new
          reply_stream.write(message.to_s)

          if @config[:load_limit] < reply_stream.buf.size
            raise TypeError, 'too large packet'
          end

          promise.resolve reply_stream
        end
        promise
      end
    end
  end
end

