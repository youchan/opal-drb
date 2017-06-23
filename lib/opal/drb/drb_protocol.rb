module DRb
  module DRbProtocol
    @protocol = [DRb::WebSocket] # default
  end

  module DRbProtocol
    def add_protocol(prot)
      @protocol.push(prot)
    end
    module_function :add_protocol

    def open(uri, config, first=true)
      @protocol.each do |prot|
        begin
          return prot.open(uri, config)
        rescue DRbBadScheme
        rescue DRbConnError
          raise($!)
        rescue
          raise(DRbConnError, "#{uri} - #{$!.inspect}")
        end
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end
    module_function :open

    def uri_option(uri, config, first=true)
      @protocol.each do |prot|
        begin
          uri, opt = prot.uri_option(uri, config)
          return uri, opt
        rescue DRbBadScheme
        end
      end
      if first && (config[:auto_load] != false)
        auto_load(uri)
        return uri_option(uri, config, false)
      end
      raise DRbBadURI, 'can\'t parse uri:' + uri
    end
    module_function :uri_option
  end
end
