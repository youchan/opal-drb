require 'sinatra'
require 'opal'

if development?
  require 'sinatra/reloader'
end

class Server < Sinatra::Base
  OPAL = Opal::Sprockets::Server.new do |server|
    server.append_path 'app'
    server.append_path 'assets'
    server.append_path '../lib'
    Opal.paths.each {|path| server.append_path path }

    server.main = 'application'
  end

  configure do
    set opal: OPAL
    enable :sessions
  end

  get '/' do
    erb :index
  end

  get "/favicon.ico" do
  end
end

