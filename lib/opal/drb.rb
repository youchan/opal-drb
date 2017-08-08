if RUBY_ENGINE == 'opal'
  module DRb
    class DRbError < RuntimeError; end
    class DRbConnError < DRbError; end
    class DRbServerNotFound < DRbError; end
    class DRbBadURI < DRbError; end
    class DRbBadScheme < DRbError; end
  end

  require 'opal/drb/version'
  require 'opal/drb/websocket'
  require 'opal/drb/drb_protocol'
  require 'opal/drb/drb_conn'
  require 'opal/drb/drb_object'
  require 'opal/drb/drb_message'
  require 'opal/drb/drb'
end
