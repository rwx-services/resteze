module Resteze
  class Authenticator
    # An authentication scheme. Strategies hold only their configuration;
    # anything mutable, such as a cached credential, goes in the `state`
    # hash the authenticator hands them, already under its lock. Because
    # that hash is shared by every strategy on the authenticator, prefix
    # the keys you store with the scheme's name.
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

      # Options may be given as a value or as something callable, so a
      # credential can be read lazily and rotated.
      def resolve(value)
        value.respond_to?(:call) ? value.call : value
      end
    end
  end
end
