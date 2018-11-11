require 'bundler/setup'
Bundler.require(:default)

require 'drb/websocket/server'

require_relative 'server'

app = Rack::Builder.app do
  server = Server.new(host: 'localhost')

  map '/' do
    use DRb::WebSocket::RackApp
    run server
  end

  map '/assets' do
    run Server::OPAL.sprockets
  end
end

require_relative './drb_server'

Rack::Server.start({
  app:    app,
  server: 'thin',
  Host:   '0.0.0.0',
  Port:   1234,
  signals: false,
})
