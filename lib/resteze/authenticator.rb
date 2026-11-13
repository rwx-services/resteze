require "resteze/synchronized_state"

module Resteze
  # The interface through which a client describes how its API
  # authenticates requests. Resteze ships no credentials and assumes no
  # scheme: the default does nothing, and `include Resteze` gives each API
  # module its own MyApi::Authenticator subclass to fill in. One instance
  # per module, shared by every thread, is reached as MyApi.authenticator.
  #
  # The client calls, for every request:
  #
  #   connection_options
  #     When the per-thread Faraday connection is built. Mutual TLS puts
  #     its certificate here.
  #   apply(request)
  #     Before sending. `request` exposes `headers`, `params` and `query`
  #     to mutate; header and query-parameter schemes add themselves here.
  #   refresh?(error, attempt)
  #     After a MyApi::AuthenticationError (401 or 403). Return true to
  #     send the request once more, for schemes whose credential can be
  #     renewed; `attempt` counts failures so far, starting at 1.
  #
  # A scheme is chosen with `authenticate_with` on the module (or `strategy`
  # inside this class), by the name a built-in registered through
  # Strategy.register or by a Strategy subclass; several may be combined.
  # Each scheme expects its credential in a module setting named by its
  # DEFAULTS, which an initializer fills through `configure`, and declaring
  # the scheme declares the setting:
  #
  #   module MyApi
  #     include Resteze
  #
  #     authenticate_with :api_key, header: "X-Api-Key"   # expects MyApi.api_key
  #   end
  #
  #   MyApi.configure { |config| config.api_key = ENV["MY_API_KEY"] }
  #
  # Any credential option also takes a Symbol naming another setting, a
  # callable for a credential that comes from somewhere other than
  # configuration, or a literal value. `MyApi.authenticator.missing_settings`
  # lists expected settings still nil, for a boot-time check.
  #
  # Every scheme is a subclass of Resteze::Authenticator::Strategy: subclass
  # it, implement `apply`, declare DEFAULTS, and pass the class to
  # `authenticate_with`.
  #
  # State lives in a mutex-guarded hash (`state`, `update_state`,
  # `synchronize`) shared by the strategies, so a strategy that caches a
  # credential need not manage threads; `apply` and `refresh?` run under
  # the lock, which is what keeps concurrent threads from all renewing a
  # credential at once.
  class Authenticator
    include Resteze::ApiModule
    include Resteze::SynchronizedState

    # What `apply` receives. `headers`, `params` and `query` are the hashes
    # the request will be sent with; `query` always goes in the query
    # string, whatever the HTTP method, unlike `params`.
    Request = Struct.new(:http_method, :path, :headers, :params, :query, keyword_init: true)

    class << self
      # Adds a built-in strategy (by name) or a custom Strategy class with
      # its options. Call it more than once to combine schemes. Without
      # arguments, returns the [class, options] pairs in effect for this
      # class, inherited from a superclass when it declares none.
      def strategy(name = nil, **options)
        return strategy_specs if name.nil? && options.empty?
        raise ArgumentError, "strategy needs a name or class before its options" if name.nil?

        klass = name.is_a?(Class) ? name : Strategy.lookup(name)
        declare_settings(klass.settings(options))
        own_strategy_specs << [klass, options]
        nil
      end

      # The module settings every configured strategy reads, in order.
      def settings
        strategy_specs.flat_map { |klass, options| klass.settings(options) }.uniq
      end

      # Those of them the strategies cannot work without.
      def required_settings
        strategy_specs.flat_map { |klass, options| klass.required_settings(options) }.uniq
      end

      # Declares those settings on the API module (`api_key`, `username`,
      # ...) so an initializer can set them through `configure` with no
      # `attr_accessor` of its own. Existing accessors are left alone.
      def declare_settings(names)
        mod = api_module
        return if mod.nil? || mod == Resteze

        names.each { |name| mod.singleton_class.attr_accessor(name) unless mod.respond_to?(name) }
      end

      def strategy_specs
        own = own_strategy_specs
        return own unless own.empty?

        superclass.respond_to?(:strategy_specs) ? superclass.strategy_specs : []
      end

      def strategy_instances
        strategy_specs.map { |klass, options| klass.new(**options) }
      end

      private

      def own_strategy_specs
        @own_strategy_specs ||= []
      end
    end

    attr_reader :strategies

    def initialize(strategies: self.class.strategy_instances)
      initialize_state
      @strategies = Array(strategies).freeze
      self.api_module = self.class.api_module
    end

    # The module this authenticator serves, and whose settings its
    # strategies read. Set by MyApi.authenticator=.
    def api_module
      @api_module || self.class.api_module
    end

    def api_module=(mod)
      @api_module = mod
      strategies.each { |strategy| strategy.api_module = mod if strategy.respond_to?(:api_module=) }
    end

    # The module settings this instance's strategies read.
    def settings
      strategies.flat_map(&:settings).uniq
    end

    # Those of them the strategies cannot work without (a strategy's
    # OPTIONAL settings, such as a key passphrase, are left out).
    def required_settings
      strategies.flat_map(&:required_settings).uniq
    end

    # The required settings that are still nil, for checking configuration
    # at boot:
    #
    #   raise "MyApi needs #{MyApi.authenticator.missing_settings.join(', ')}" if MyApi.authenticator.missing_settings.any?
    def missing_settings
      required_settings.select { |name| api_module.try(name).nil? }
    end

    # Faraday connection options merged from every strategy, such as `ssl:`.
    def connection_options
      strategies.map(&:connection_options).reduce({}) { |merged, options| merged.deep_merge(options) }
    end

    # Lets every strategy add its credential to the request. Returns it.
    def apply(request)
      return request if strategies.empty?

      synchronize { |state| strategies.each { |strategy| strategy.apply(request, state) } }
      request
    end

    # True when any strategy renewed its credential and wants one retry.
    def refresh?(error, attempt)
      return false if strategies.empty?

      synchronize { |state| strategies.any? { |strategy| strategy.refresh?(error, attempt, state) } }
    end
  end
end

require "resteze/authenticator/strategy"
require "resteze/authenticator/api_key"
require "resteze/authenticator/basic"
require "resteze/authenticator/bearer"
require "resteze/authenticator/mtls"
