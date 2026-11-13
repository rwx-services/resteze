module Resteze
  class Authenticator
    # An authentication scheme. Strategies hold only their configuration;
    # anything mutable, such as a cached credential, goes in the `state`
    # hash the authenticator hands them, already under its lock. Because
    # that hash is shared by every strategy on the authenticator, prefix
    # the keys you store with the scheme's name.
    #
    # Credential options name module settings. A Symbol such as `:api_key`
    # reads `MyApi.api_key`, which an initializer fills through
    # `MyApi.configure`, on every request. Each built-in defaults to the
    # obvious setting (see its DEFAULTS), and declaring the scheme declares
    # the setting on the module, so `config.api_key = ...` needs no
    # `attr_accessor`. A callable or a literal works in place of a Symbol.
    #
    # To add a scheme, subclass this, implement `apply`, declare DEFAULTS
    # for any options that should read settings, and pass the class to
    # `authenticate_with` with its options.
    class Strategy
      # Option defaults; Symbol values are settings read from the module.
      DEFAULTS = {}.freeze

      # Options the scheme works without (a passphrase for a key that is
      # not encrypted). Their settings are declared on the module like any
      # other but never reported by `missing_settings`.
      OPTIONAL = [].freeze

      attr_accessor :api_module

      # Names a scheme for `authenticate_with :name`. Each built-in registers
      # itself; a gem providing a scheme can do the same.
      def self.register(name, klass)
        registry[name.to_sym] = klass
      end

      def self.registry
        @registry ||= {}
      end

      def self.lookup(name)
        registry.fetch(name.to_sym) do
          raise ArgumentError, "unknown authentication strategy #{name.inspect}; known: #{registry.keys.join(', ')}"
        end
      end

      # The module settings these options (over the defaults) read.
      def self.settings(options = {})
        effective_options(options).values.grep(Symbol)
      end

      # Those of them the scheme cannot work without.
      def self.required_settings(options = {})
        effective_options(options).except(*self::OPTIONAL).values.grep(Symbol)
      end

      def self.effective_options(options)
        self::DEFAULTS.merge(options)
      end
      private_class_method :effective_options

      # The module settings this instance reads: DEFAULTS as overridden by
      # the credential options it was built with.
      def settings
        self.class.settings(credential_options)
      end

      def required_settings
        self.class.required_settings(credential_options)
      end

      # The credential options as given to the constructor, so `settings`
      # reflects a renamed setting; schemes implement it.
      def credential_options
        {}
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

      # For constructors: rejects nil for an option the scheme needs.
      def required!(name, value)
        raise ArgumentError, "#{name}: is required" if value.nil?

        value
      end

      # A Symbol reads the named setting from the module (nil when there is
      # no module or no such setting), a callable is called, anything else
      # is used as is.
      def resolve(value)
        return value.call if value.respond_to?(:call)
        return value unless value.is_a?(Symbol)

        api_module.try(value)
      end

      # As `resolve`, but a nil result is a configuration error that names
      # what to set.
      def resolve!(option, value)
        resolved = resolve(value)
        return resolved unless resolved.nil?

        where  = value.is_a?(Symbol) ? "#{api_module || 'the API module'}.#{value} is not set" : "#{option}: resolved to nil"
        scheme = self.class.name&.demodulize&.underscore || "custom"
        raise ArgumentError, "#{where}; the #{scheme} authentication strategy needs it"
      end
    end
  end
end
