require 'opal'
require 'native'
require 'opal/drb'

obj = DRb::DRbObject.new_with_uri "ws://127.0.0.1:1234"
DRb.start_service("ws://127.0.0.1:1234/callback")

def interval(interval, &func)
  %x(
    setInterval(func, interval);
  )
end

obj.test.then do |res|
  puts res
end

obj.add_callback do |text|
  puts text
end

i = 0
interval(1000) do
  obj.notify("notification #{i}")
  i += 1
end
