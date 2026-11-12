module Resteze
  class RateLimiter
    # At most `limit` requests in any trailing `window` seconds. Exact: it
    # keeps the time of each admitted request until it ages out, so memory
    # is bounded by `limit`.
    class SlidingWindow < Strategy
      attr_reader :limit, :window

      def initialize(limit:, window:)
        super()
        @limit  = Strategy.integer!(:limit, limit)
        @window = Strategy.number!(:window, window)
      end

      def acquire(state, now)
        times = expire(state, now)
        return times.first + window - now if times.size >= limit

        times << now
        0
      end

      def describe(state, now)
        times = expire(state, now)
        RateLimit.new(limit:, remaining: limit - times.size, reset: times.first && (times.first + window))
      end

      private

      def expire(state, now)
        times = (state[:times] ||= [])
        times.shift while times.first && times.first <= now - window
        times
      end
    end
  end
end
