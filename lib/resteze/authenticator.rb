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
  # The built-in schemes are chosen with `strategy`, and several may be
  # combined, for example mutual TLS with an API key. The credential is
  # usually a callable reading a module setting that an initializer filled
  # through `configure`, so it is read on every request:
  #
  #   module MyApi
  #     include Resteze
  #
  #     class << self
  #       attr_accessor :api_key
  #     end
  #
  #     class Authenticator
  #       strategy :api_key, header: "X-Api-Key", value: -> { MyApi.api_key }
  #     end
  #   end
  #
  #   MyApi.configure { |config| config.api_key = ENV["MY_API_KEY"] }
  #
  #   strategy :api_key, header: "X-Api-Key", value: ...     # or query: "api_key"
  #   strategy :basic,   username: ..., password: ...
  #   strategy :bearer,  token: ...                          # scheme: "Token" for other prefixes
  #   strategy :mtls,    cert: ..., key: ..., ca_file: ...   # PEM strings or paths
  #
  # Each built-in is a subclass of Resteze::Authenticator::Strategy, and a
  # custom scheme is the same: subclass it, implement `apply`, and pass the
  # class to `strategy`. Schemes that fetch or sign tokens (OAuth 2.0, JWT)
  # need extra dependencies and are meant to live in their own gems as
  # further Strategy subclasses.
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

        own_strategy_specs << [name.is_a?(Class) ? name : Strategy.lookup(name), options]
        nil
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
    attr_writer :api_module

    def initialize(strategies: self.class.strategy_instances, strategy: nil)
      initialize_state
      @strategies = Array(strategy || strategies).freeze
    end

    # The module this authenticator serves. Set by MyApi.authenticator=.
    def api_module
      @api_module || self.class.api_module
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
