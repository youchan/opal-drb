require 'drb/drb'
require 'drb/websocket/server'

class SampleObject
  def initialize
    @callbacks = []
  end

  def test
    "ACK!"
  end

  def notify(text)
    @callbacks.each do |callback|
      callback.call(text)
    end
  end

  def add_callback(&callback)
    @callbacks << callback
  end
end

DRb.start_service("ws://127.0.0.1:1234", SampleObject.new)
