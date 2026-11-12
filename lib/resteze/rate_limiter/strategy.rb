module Resteze
  class RateLimiter
    # A rate-limiting algorithm. Strategies are stateless objects: all
    # bookkeeping goes in the `state` hash the limiter hands them, already
    # under the limiter's lock. Times are Floats of seconds since the epoch.
    #
    # To add one, subclass this, implement `acquire`, and pass the class to
    # `strategy` instead of a name.
    class Strategy
      BUILT_IN = {
        fixed_window: "Resteze::RateLimiter::FixedWindow",
        sliding_window: "Resteze::RateLimiter::SlidingWindow",
        token_bucket: "Resteze::RateLimiter::TokenBucket",
        leaky_bucket: "Resteze::RateLimiter::LeakyBucket"
      }.freeze

      def self.lookup(name)
        class_name = BUILT_IN[name.to_sym] or
          raise ArgumentError, "unknown rate-limit strategy #{name.inspect}; known: #{BUILT_IN.keys.join(', ')}"

        class_name.constantize
      end

      def self.positive!(name, value)
        raise ArgumentError, "#{name} must be a positive number, got #{value.inspect}" unless value.to_f.positive?

        value
      end

      # Admit one request now and return 0, or return the seconds until one
      # could be admitted, having recorded nothing.
      def acquire(_state, _now)
        0
      end

      # Learn from a Response or Error the API sent back. Most algorithms
      # have nothing to learn; FixedWindow syncs with the API's headers.
      def observe(state, response, now); end

      # The strategy's current view as a Resteze::RateLimit, for `rate_limit`.
      def describe(_state, _now)
        nil
      end
    end
  end
end
