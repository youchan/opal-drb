require 'opal'
require 'native'
require 'opal/drb'

puts ">>>>>>>> Example"

remote = DRb::DRbObject.new_with_uri "ws://127.0.0.1:1234"

promise = remote.get
promise.then do |obj|
  obj.test.then do |res|
    puts res
  end
end
