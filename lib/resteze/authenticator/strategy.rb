module Resteze
  class Authenticator
    # An authentication scheme. Strategies hold only their configuration;
    # anything mutable, such as a cached credential, goes in the `state`
    # hash the authenticator hands them, already under its lock. Because
    # that hash is shared by every strategy on the authenticator, prefix
    # the keys you store with the scheme's name.
    #
    # Credential options take a value or a callable. The callable form is
    # the usual one: `value: -> { MyApi.api_key }` reads a setting that an
    # initializer filled through `MyApi.configure`, on every request, so a
    # rotated credential takes effect without a restart.
    #
    # To add a scheme, subclass this, implement `apply`, and pass the class
    # to `strategy` with its options.
    class Strategy
      BUILT_IN = {
        api_key: "Resteze::Authenticator::ApiKey",
        basic: "Resteze::Authenticator::Basic",
        bearer: "Resteze::Authenticator::Bearer",
        mtls: "Resteze::Authenticator::Mtls"
      }.freeze

      def self.lookup(name)
        class_name = BUILT_IN[name.to_sym] or
          raise ArgumentError, "unknown authentication strategy #{name.inspect}; known: #{BUILT_IN.keys.join(', ')}"

        class_name.constantize
      end

      def self.required!(name, value)
        raise ArgumentError, "#{name}: is required" if value.nil?

        value
      end

      # Faraday connection options this scheme needs, merged into the
      # connection when it is built. Most schemes need none.
      def connection_options
        {}
      end

      # Add the credential to `request.headers`, `request.params` or
      # `request.query`.
      def apply(request, state); end

      # After a MyApi::AuthenticationError: renew the credential and return
      # true to have the request sent once more, or return false.
      def refresh?(_error, _attempt, _state)
        false
      end

      private

      # A callable is called, anything else is used as is.
      def resolve(value)
        value.respond_to?(:call) ? value.call : value
      end

      # As `resolve`, but a nil result (an unset setting, say) is an error
      # rather than an empty credential on the wire.
      def resolve!(option, value)
        resolved = resolve(value)
        return resolved unless resolved.nil?

        raise ArgumentError, "#{option}: for the #{self.class.name.demodulize.underscore} authentication strategy " \
                             "resolved to nil; is the setting it reads configured?"
      end
    end
  end
end
