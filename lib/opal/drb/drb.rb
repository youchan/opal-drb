require 'corelib/marshal'
require 'promise'

module DRb
  class DRbUnknownError < DRbError
    def initialize(unknown)
      @unknown = unknown
      super(unknown.name)
    end
    attr_reader :unknown

    def self._load(s)
      Marshal::load(s)
    end

    def _dump(lv)
      Marshal::dump(@unknown)
    end
  end

  class DRbRemoteError < DRbError
    def initialize(error)
      @reason = error.class.to_s
      super("#{error.message} (#{error.class})")
      set_backtrace(error.backtrace)
    end

    attr_reader :reason
  end

  class DRbIdConv
    def to_obj(ref)
      ObjectSpace._id2ref(ref)
    end

    def to_id(obj)
      obj.nil? ? nil : obj.__id__
    end
  end

  module DRbUndumped
    def _dump(dummy)
      raise TypeError, 'can\'t dump'
    end
  end

  class DRbUnknown
    def initialize(err, buf)
      case err.to_s
      when /uninitialized constant (\S+)/
        @name = $1
      when /undefined class\/module (\S+)/
        @name = $1
      else
        @name = nil
      end
      @buf = buf
    end

    attr_reader :name
    attr_reader :buf

    def self._load(s)
      begin
        Marshal::load(s)
      rescue NameError, ArgumentError
        DRbUnknown.new($!, s)
      end
    end

    def _dump(lv)
      @buf
    end

    def reload
      self.class._load(@buf)
    end

    def exception
      DRbUnknownError.new(self)
    end
  end

  class DRbArray
    def initialize(ary)
      @ary = ary.collect { |obj|
        if obj.kind_of? DRbUndumped
          DRbObject.new(obj)
        else
          begin
            Marshal.dump(obj)
            obj
          rescue
            DRbObject.new(obj)
          end
        end
      }
    end

    def self._load(s)
      Marshal::load(s)
    end

    def _dump(lv)
      Marshal.dump(@ary)
    end
  end

end
