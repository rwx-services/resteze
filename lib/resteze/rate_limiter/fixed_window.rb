module Resteze
  class RateLimiter
    # At most `limit` requests per `window` seconds, counted in consecutive
    # windows aligned to the first request. When a window is spent, the next
    # request waits for the next window.
    #
    # With `headers: true` the budget and window follow the API's own
    # X-RateLimit-Limit, X-RateLimit-Remaining and X-RateLimit-Reset headers
    # as responses come back, so the local view matches the server's even
    # across processes sharing one key. Pass a Hash to name other headers.
    # `reset: :epoch` (the default) reads the reset header as a time;
    # `reset: :seconds` reads it as a countdown. `limit:` may be omitted when
    # the API sends it, or even when it sends only the remaining count.
    #
    # Syncing is conservative: within a window the local remaining count and
    # the server's are both honoured by taking the lower, since requests
    # admitted locally after the server answered are not in its number yet.
    # A reset later than the local window's end starts a fresh window.
    class FixedWindow < Strategy
      attr_reader :limit, :window, :headers, :reset_format

      def initialize(window:, limit: nil, headers: false, reset: :epoch)
        super()
        @limit        = limit && Strategy.integer!(:limit, limit)
        @window       = Strategy.number!(:window, window)
        @headers      = headers == true ? {} : headers
        @reset_format = reset
        raise ArgumentError, "limit: is required unless headers: syncs it from the API" if @limit.nil? && !@headers
        raise ArgumentError, "reset: must be :epoch or :seconds" unless %i[epoch seconds].include?(reset)
      end

      def acquire(state, now)
        roll_window(state, now)
        remaining = state[:remaining]
        return 0 if remaining.nil? # no budget known yet
        return state[:window_started] + window - now if remaining <= 0

        state[:remaining] = remaining - 1
        0
      end

      def observe(state, response, now)
        return unless headers

        reported = RateLimit.from_headers(response.http_headers, headers)
        return unless reported

        roll_window(state, now)
        state[:limit] = reported.limit || state[:limit] || limit
        sync_window(state, reported, now)
        sync_remaining(state, reported)
      end

      def describe(state, now)
        roll_window(state, now)
        remaining = state[:remaining] && [state[:remaining], 0].max
        RateLimit.new(limit: state[:limit], remaining:, reset: state[:window_started] + window)
      end

      private

      # Starts the first window at `now`; afterwards advances by whole
      # windows so they stay aligned to that first request.
      def roll_window(state, now)
        started = state[:window_started]
        return if started && now < started + window

        state[:window_started] = started ? aligned_start(started, now) : now
        state[:limit]        ||= limit
        state[:remaining]      = state[:limit]
      end

      def aligned_start(started, now)
        started + (((now - started) / window).floor * window)
      end

      # Aligns the local window to the server's reset. A reset beyond the
      # current window means the server has moved on: start fresh.
      def sync_window(state, reported, now)
        reset_at = trusted_reset(reported.reset, now)
        return unless reset_at

        fresh = reset_at > state[:window_started] + window + 1e-6
        state[:window_started] = reset_at - window
        state[:remaining]      = state[:limit] if fresh
      end

      # Resets that are non-finite or further than one window away are not
      # trusted; the latter is clamped to one window from now.
      def trusted_reset(reset, now)
        return unless reset

        reset_at = reset_format == :seconds ? now + reset : reset.to_f
        return unless reset_at.finite?

        [reset_at, now + window].min
      end

      def sync_remaining(state, reported)
        return unless reported.remaining

        local = state[:remaining]
        state[:remaining] = local.nil? ? reported.remaining : [local, reported.remaining].min
      end
    end
  end
end
