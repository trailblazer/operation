module Trailblazer
  module Operation::PublicCall
    # This is the outer-most public `call` method that gets invoked when calling `Create.()`.
    # The signature of this is `params, options, *containers`. This was a mistake, as the
    # first argument could've been part of `options` hash in the first place.
    #
    # Create.(params, runtime_data, *containers)
    #   #=> Result<Context...>
    #
    # In workflows/Nested compositions, this method is not used anymore and it might probably
    # get removed in future versions of TRB. Currently, we use Operation::__call__ as an alternative.
    #
    #
    # @note Do not override this method as it will be removed in future versions. Also, you will break tracing.
    # @return Operation::Railway::Result binary result object
    def call(options = {}, flow_options = {}, **circuit_options)
      return call_with_circuit_interface(options, **circuit_options) if options.is_a?(Array) # This is kind of a hack that could be well hidden if Ruby had method overloading. Goal is to simplify the call thing as we're fading out Operation::public_call anyway.

      call_with_public_interface(options, flow_options, **circuit_options)
    end

    # Default {@activity} call interface which doesn't accept {circuit_options}
    #
    # @param [Array] args => [ctx, flow_options]
    #
    # @return [Operation::Railway::Result]
    #
    # @private
    def call_with_public_interface(options, flow_options, invoke_class: Activity::TaskWrap, **circuit_options)
      flow_options  = flow_options_for_public_call(flow_options)

      # In Ruby < 3, calling Op.(params: {}, "current_user" => user) results in both {circuit_options} and {options} containing variables.
      # In Ruby 3.0, **circuit_options is always empty.
      options       = circuit_options.any? ? circuit_options.merge(options) : options

      ctx           = options_for_public_call(options, flow_options)

      # call the activity.
      # This will result in invoking {::call_with_circuit_interface}.
      signal, (ctx, flow_options) = invoke_class.invoke(
        self,
        [ctx, flow_options],
        exec_context: new,
        wrap_static: initial_wrap_static,
      )

      # Result is successful if the activity ended with an End event derived from Railway::End::Success.
      Operation::Railway::Result(signal, ctx, flow_options)
    end

    # This interface is used for all nested OPs (and the outer-most, too).
    #
    # @param [Array] args - Contains [ctx, flow_options]
    # @param [Hash]  circuit_options - Options to configure activity circuit
    #
    # @return [signal, [ctx, flow_options]]
    #
    # @private
    def call_with_circuit_interface(args, **circuit_options)
      strategy_call(args, **circuit_options) # FastTrack#call
    end

    def options_for_public_call(*args)
      Operation::PublicCall.options_for_public_call(*args)
    end

    # Compile a Context object to be passed into the Activity::call.
    # @private
    def self.options_for_public_call(options, flow_options = {})
      Trailblazer::Context(options, {}, flow_options[:context_options])
    end

    # @semi=public
    def flow_options_for_public_call(options = {})
      options
    end

    # TODO: remove when we stop supporting < 3.0.
    def call_with_flow_options(options, flow_options)
      raise "[Trailblazer] `Operation.call_with_flow_options is deprecated in Ruby 3.0. Use `Operation.(options, flow_options)`" if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new("3.0.0")
      call_with_public_interface(options, flow_options, {invoke_class: Activity::TaskWrap})
    end

    def initial_wrap_static(*)
      Activity::TaskWrap::Pipeline.new([["task_wrap.call_task", method(:call_task)]])
    end

    def call_task(wrap_ctx, original_args) # DISCUSS: copied from {TaskWrap.call_task}.
      op = wrap_ctx[:task]

      original_arguments, original_circuit_options = original_args

      # Call the actual task we're wrapping here.
      # puts "~~~~wrap.call: #{task}"
      return_signal, return_args = op.call_with_circuit_interface(original_arguments, **original_circuit_options)

      # DISCUSS: do we want original_args here to be passed on, or the "effective" return_args which are different to original_args now?
      wrap_ctx = wrap_ctx.merge(return_signal: return_signal, return_args: return_args)

      return wrap_ctx, original_args
    end
  end
end
