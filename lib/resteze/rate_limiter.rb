module Resteze
  # The interface through which a client describes, and responds to, its
  # API's rate limiting. Resteze assumes nothing about the mechanics: every
  # method here is a no-op until a strategy is chosen or a method overridden,
  # and `include Resteze` gives each API module its own MyApi::RateLimiter
  # subclass to fill in. One instance per module, shared by every thread, is
  # reached as MyApi.rate_limiter.
  #
  # The client calls, for every request:
  #
  #   before_request(method, path, params:, headers:)
  #     Before sending. With a strategy, waits until the request fits the
  #     budget. Override to throttle differently, or raise to refuse.
  #   track(response_or_error)
  #     After every Response and every MyApi::Error. With a strategy, lets
  #     it learn from what the API reported.
  #   retry?(error, attempt)
  #     After a MyApi::RateLimitError. Return true to retry; `attempt`
  #     counts failed attempts so far, starting at 1. Default false.
  #   retry_after(error)
  #     Seconds to wait before that retry. Default: the error's Retry-After.
  #
  # and whenever something reads `rate_limit` on a Response or an Error:
  #
  #   rate_limit(response_or_error)
  #     Whatever describes the limit. With a strategy, a Resteze::RateLimit
  #     of the strategy's current view; otherwise nil.
  #
  # Both a Response and a MyApi::Error answer http_status, http_headers and
  # http_body; a Response has the parsed body in `data`, an Error in `json_body`.
  #
  # The four common algorithms are built in and chosen with `strategy`:
  #
  #   module Braze
  #     class RateLimiter
  #       strategy :fixed_window, limit: 250_000, window: 3600, headers: true
  #     end
  #   end
  #
  #   strategy :fixed_window,   limit: 100, window: 60            # N per clock window
  #   strategy :sliding_window, limit: 100, window: 60            # N per trailing window
  #   strategy :token_bucket,   capacity: 100, refill_rate: 10    # bursts, refilled per second
  #   strategy :leaky_bucket,   capacity: 100, leak_rate: 10      # smoothed, drained per second
  #
  # `headers: true` on a fixed window syncs the local count and window with
  # the API's X-RateLimit-* headers (or `headers: { remaining: "...", ... }`
  # for other names), which is how Braze and JD Power report theirs.
  #
  # State lives in a mutex-guarded hash so a subclass need not think about
  # threads: read a snapshot with `state`, change it with `update_state`, or
  # work on the live hash inside `synchronize` for read-modify-write
  # sequences. Avoid instance variables. Waiting always happens outside the
  # lock, so one thread's wait never blocks another thread's bookkeeping.
  class RateLimiter
    class << self
      # Chooses the built-in strategy (by name) or a custom Strategy class
      # that instances of this limiter use. Without arguments, returns the
      # configured [class, options] pair or nil.
      def strategy(name = nil, **options)
        return @strategy if name.nil?

        klass = name.is_a?(Class) ? name : Strategy.lookup(name)
        @strategy = [klass, options]
        nil
      end

      # The configured [class, options] pair, inherited from the superclass
      # when this class declares none.
      def strategy_spec
        @strategy || (superclass.respond_to?(:strategy_spec) ? superclass.strategy_spec : nil)
      end

      def strategy_instance
        spec = strategy_spec
        spec && spec[0].new(**spec[1])
      end
    end

    attr_reader :strategy

    def initialize(strategy: self.class.strategy_instance, clock: nil, sleeper: nil)
      @mutex    = Mutex.new
      @state    = {}
      @strategy = strategy
      @clock    = clock   || -> { Time.now.to_f }
      @sleeper  = sleeper || ->(seconds) { sleep(seconds) }
    end

    # Receives (method, path, params:, headers:); the default needs none.
    def before_request(*, **)
      throttle if strategy
    end

    def track(response)
      return unless strategy

      synchronize { |state| strategy.observe(state, response, now) }
    end

    def rate_limit(_response)
      return unless strategy

      synchronize { |state| strategy.describe(state, now) }
    end

    def retry?(_error, _attempt)
      false
    end

    def retry_after(error)
      error.retry_after
    end

    # Waits, outside the lock, until the strategy admits one request, and
    # records it. Returns the total seconds waited.
    def throttle
      waited = 0.0
      loop do
        wait = synchronize { |state| strategy.acquire(state, now) }
        break if wait <= 0

        @sleeper.call(wait)
        waited += wait
      end
      waited
    end

    # A snapshot of the limiter's state.
    def state
      synchronize(&:dup)
    end

    def update_state(**values)
      synchronize { |state| state.merge!(values) }
    end

    # Yields the live state hash under the lock. Re-entrant, so `state` and
    # `update_state` may be called inside the block.
    def synchronize
      return yield(@state) if @mutex.owned?

      @mutex.synchronize { yield(@state) }
    end

    private

    def now
      @clock.call
    end
  end
end

require "resteze/rate_limiter/strategy"
require "resteze/rate_limiter/fixed_window"
require "resteze/rate_limiter/sliding_window"
require "resteze/rate_limiter/token_bucket"
require "resteze/rate_limiter/leaky_bucket"
