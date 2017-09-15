class InvokeMethod
  def initialize(drb_server, client)
    @drb_server = drb_server
    @client = client
  end

  def perform
    @result = nil
    @succ = false

    setup_message

    if @block
      @result = perform_with_block
    else
      @result = perform_without_block
    end

    @succ = true
    if @msg_id == :to_ary && @result.class == Array
      @result = DRbArray.new(@result)
    end
    return @succ, @result
  rescue StandardError, ScriptError, Interrupt
    @result = $!
    return @succ, @result
  end

  private
  def init_with_client
    obj, msg, argv, block = @client.recv_request
    @obj = obj
    @msg_id = msg.intern
    @argv = argv
    @block = block
  end


  def any_to_s(obj)
    obj.to_s + ":#{obj.class}"
  rescue
    "#<#{obj.class}:0x#{obj.__id__.to_s(16)}>"
  end

  def check_insecure_method(obj, msg_id)
    return true if Proc === obj && msg_id == :__drb_yield
    raise(ArgumentError, "#{any_to_s(msg_id)} is not a symbol") unless Symbol == msg_id.class
    raise(SecurityError, "insecure method `#{msg_id}'") if insecure_method?(msg_id)

    if obj.private_methods.include?(msg_id)
      desc = any_to_s(obj)
      raise NoMethodError, "private method `#{msg_id}' called for #{desc}"
    else
      true
    end
  end

  def setup_message
    init_with_client
    check_insecure_method(@obj, @msg_id)
  end

  def perform_without_block
    if Proc === @obj && @msg_id == :__drb_yield
      if @argv.size == 1
        ary = @argv
      else
        ary = [@argv]
      end
      ary.collect(&@obj)[0]
    else
      @obj.__send__(@msg_id, *@argv)
    end
  end

  INSECURE_METHOD = [
    :__send__
  ]

  # Has a method been included in the list of insecure methods?
  def insecure_method?(msg_id)
    INSECURE_METHOD.include?(msg_id)
  end
end

