module Resteze
  class RateLimiter
    # A bucket of `capacity` tokens refilled at `refill_rate` tokens per
    # second. Each request takes one token; an empty bucket waits for the
    # next refill. Allows bursts up to `capacity` after a quiet period.
    class TokenBucket < Strategy
      attr_reader :capacity, :refill_rate

      def initialize(capacity:, refill_rate:)
        super()
        @capacity    = Strategy.positive!(:capacity, capacity).to_f
        @refill_rate = Strategy.positive!(:refill_rate, refill_rate).to_f
      end

      def acquire(state, now)
        tokens = refill(state, now)
        return (1 - tokens) / refill_rate if tokens < 1

        state[:tokens] = tokens - 1
        0
      end

      def describe(state, now)
        tokens = refill(state, now)
        RateLimit.new(limit: capacity.to_i, remaining: tokens.floor,
                      reset: tokens < 1 ? now + ((1 - tokens) / refill_rate) : nil)
      end

      private

      def refill(state, now)
        last   = state[:refilled_at] || now
        tokens = [capacity, state.fetch(:tokens, capacity) + ((now - last) * refill_rate)].min
        state[:refilled_at] = now
        state[:tokens]      = tokens
      end
    end
  end
end
