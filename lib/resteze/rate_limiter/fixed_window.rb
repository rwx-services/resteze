module Resteze
  class RateLimiter
    # At most `limit` requests per `window` seconds, counted in consecutive
    # windows aligned to the first request. When a window is spent, the next
    # request waits for the next window. This is how Braze and JD Power count.
    #
    # With `headers: true` the count and window follow the API's own
    # X-RateLimit-Limit, X-RateLimit-Remaining and X-RateLimit-Reset headers
    # as responses come back, so the local view matches the server's even
    # across processes sharing one key. Pass a Hash to name other headers.
    # `reset: :epoch` (the default) reads the reset header as a time;
    # `reset: :seconds` reads it as a countdown. `limit:` may be omitted when
    # the API sends it.
    class FixedWindow < Strategy
      attr_reader :limit, :window, :headers, :reset_format

      def initialize(window:, limit: nil, headers: false, reset: :epoch)
        super()
        @limit        = limit && Strategy.positive!(:limit, limit)
        @window       = Strategy.positive!(:window, window).to_f
        @headers      = headers == true ? {} : headers
        @reset_format = reset
        raise ArgumentError, "limit: is required unless headers: syncs it from the API" if @limit.nil? && !@headers
        raise ArgumentError, "reset: must be :epoch or :seconds" unless %i[epoch seconds].include?(reset)
      end

      def acquire(state, now)
        roll_window(state, now)
        return 0 if state[:limit].nil?

        if state[:count] >= state[:limit]
          state[:window_started] + window - now
        else
          state[:count] += 1
          0
        end
      end

      def observe(state, response, now)
        return unless headers

        reported = RateLimit.from_headers(response.http_headers, headers)
        return unless reported

        state[:limit] = reported.limit || state[:limit] || limit
        sync_count(state, reported)
        sync_window(state, reported, now)
      end

      def describe(state, now)
        roll_window(state, now)
        remaining = state[:limit] && [state[:limit] - state[:count], 0].max
        RateLimit.new(limit: state[:limit], remaining:, reset: state[:window_started] + window)
      end

      private

      # Starts the first window at `now`; afterwards advances by whole
      # windows so they stay aligned to that first request.
      def roll_window(state, now)
        started = state[:window_started]
        return if started && now < started + window

        elapsed_windows        = started ? ((now - started) / window).floor : 0
        state[:window_started] = started ? started + (elapsed_windows * window) : now
        state[:count]          = 0
        state[:limit]        ||= limit
      end

      def sync_count(state, reported)
        return unless reported.remaining && state[:limit]

        state[:count] = state[:limit] - reported.remaining
      end

      def sync_window(state, reported, now)
        return unless reported.reset

        reset_at = reset_format == :seconds ? now + reported.reset : reported.reset.to_f
        state[:window_started] = reset_at - window
      end
    end
  end
end
