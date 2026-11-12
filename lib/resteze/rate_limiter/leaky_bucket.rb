module Resteze
  class RateLimiter
    # A bucket that holds up to `capacity` requests and drains at `leak_rate`
    # requests per second. Each request adds one unit; a full bucket waits
    # for enough to drain. Unlike a token bucket it smooths bursts into a
    # steady rate rather than allowing them.
    class LeakyBucket < Strategy
      attr_reader :capacity, :leak_rate

      def initialize(capacity:, leak_rate:)
        super()
        @capacity  = Strategy.number!(:capacity, capacity)
        @leak_rate = Strategy.number!(:leak_rate, leak_rate)
      end

      def acquire(state, now)
        level = drain(state, now)
        return (level + 1 - capacity) / leak_rate if level + 1 > capacity

        state[:level] = level + 1
        0
      end

      def describe(state, now)
        level = drain(state, now)
        RateLimit.new(limit: capacity.to_i, remaining: (capacity - level).floor,
                      reset: level.positive? ? now + (level / leak_rate) : nil)
      end

      private

      def drain(state, now)
        last  = state[:leaked_at] || now
        level = [0.0, state.fetch(:level, 0.0) - ((now - last) * leak_rate)].max
        state[:leaked_at] = now
        state[:level]     = level
      end
    end
  end
end
