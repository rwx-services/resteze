require "test_helper"

module Resteze
  class RateLimiter
    class StrategiesTest < Minitest::Spec
      # A limiter with a controllable clock whose sleeps advance the clock
      # instead of waiting.
      class FakeTime
        attr_reader :now, :sleeps

        def initialize(start = 1_000.0)
          @now    = start
          @sleeps = []
        end

        def clock = -> { @now }

        def sleeper
          lambda do |seconds|
            @sleeps << seconds.round(6)
            @now += seconds
          end
        end

        def advance(seconds) = @now += seconds
      end

      def limiter_with(strategy)
        time = FakeTime.new
        [Resteze::RateLimiter.new(strategy:, clock: time.clock, sleeper: time.sleeper), time]
      end

      def response_with(headers)
        Resteze::Response.new.tap { |r| r.http_headers = headers }
      end

      describe "Strategy.lookup" do
        it "resolves the four built-in names" do
          assert_equal FixedWindow,   Strategy.lookup(:fixed_window)
          assert_equal SlidingWindow, Strategy.lookup("sliding_window")
          assert_equal TokenBucket,   Strategy.lookup(:token_bucket)
          assert_equal LeakyBucket,   Strategy.lookup(:leaky_bucket)
        end

        it "rejects unknown names and non-positive options" do
          assert_raises(ArgumentError) { Strategy.lookup(:bucket_of_tokens) }
          assert_raises(ArgumentError) { FixedWindow.new(limit: 0, window: 60) }
          assert_raises(ArgumentError) { FixedWindow.new(window: 60) }
          assert_raises(ArgumentError) { FixedWindow.new(limit: 1, window: 60, reset: :soon) }
          assert_raises(ArgumentError) { TokenBucket.new(capacity: 10, refill_rate: -1) }
        end

        it "coerces options so strings from the environment work or fail at configuration time" do
          strategy = FixedWindow.new(limit: "2", window: "60")

          assert_equal 2, strategy.limit
          assert_in_delta 60.0, strategy.window
          assert_in_delta 2.5, TokenBucket.new(capacity: "2.5", refill_rate: "1").capacity
          assert_raises(ArgumentError) { FixedWindow.new(limit: "two", window: 60) }
          assert_raises(ArgumentError) { SlidingWindow.new(limit: "1.5", window: 60) }
          assert_raises(ArgumentError) { LeakyBucket.new(capacity: Float::INFINITY, leak_rate: 1) }
        end
      end

      describe FixedWindow do
        it "admits limit requests per window, then waits for the next window" do
          limiter, time = limiter_with(FixedWindow.new(limit: 3, window: 60))

          3.times { assert_equal 0, limiter.throttle }
          assert_equal 3, limiter.rate_limit(nil).limit
          assert_equal 0, limiter.rate_limit(nil).remaining

          assert_in_delta 60, limiter.throttle, 0.001
          assert_equal [60.0], time.sleeps
          assert_equal 2, limiter.rate_limit(nil).remaining
        end

        it "counts in consecutive windows from the first request" do
          limiter, time = limiter_with(FixedWindow.new(limit: 2, window: 10))

          limiter.throttle
          time.advance(9)
          limiter.throttle
          time.advance(2) # a new window started at t+10

          assert_equal 0, limiter.throttle
          assert_equal 1, limiter.rate_limit(nil).remaining
          assert_in_delta 1_020, limiter.rate_limit(nil).reset, 0.001
        end

        it "syncs count, limit and window from the API's headers" do
          limiter, time = limiter_with(FixedWindow.new(window: 3600, headers: true))

          assert_equal 0, limiter.throttle # no limit known yet: never waits
          limiter.track(response_with("X-RateLimit-Limit" => "5", "X-RateLimit-Remaining" => "1",
                                      "X-RateLimit-Reset" => (time.now + 30).to_i.to_s))

          assert_equal 1, limiter.rate_limit(nil).remaining
          assert_equal 0, limiter.throttle
          assert_in_delta 30, limiter.throttle, 1 # window spent until the API's reset
          assert_equal 4, limiter.rate_limit(nil).remaining
        end

        it "reads a countdown reset with reset: :seconds and custom header names" do
          strategy = FixedWindow.new(limit: 10, window: 60, reset: :seconds,
                                     headers: { remaining: "RateLimit-Remaining", reset: "RateLimit-Reset" })
          limiter, time = limiter_with(strategy)

          limiter.track(response_with("RateLimit-Remaining" => "0", "RateLimit-Reset" => "15"))

          assert_in_delta 15, limiter.throttle, 0.001
          assert_equal [15.0], time.sleeps
        end

        it "ignores headers when not asked to sync" do
          limiter, = limiter_with(FixedWindow.new(limit: 10, window: 60))
          limiter.track(response_with("X-RateLimit-Remaining" => "0"))

          assert_equal 0, limiter.throttle
        end

        it "honours a reported remaining count even when the API never sends the limit" do
          limiter, time = limiter_with(FixedWindow.new(window: 60, headers: true))
          limiter.track(response_with("X-RateLimit-Remaining" => "0"))

          assert_in_delta 60, limiter.throttle, 0.001
          assert_equal [60.0], time.sleeps
          assert_nil limiter.rate_limit(nil).limit
        end

        it "keeps the lower of the local and reported remaining within a window" do
          limiter, = limiter_with(FixedWindow.new(limit: 10, window: 60, headers: true))
          8.times { limiter.throttle }
          limiter.track(response_with("X-RateLimit-Remaining" => "5")) # answered before 6 of ours were sent

          assert_equal 2, limiter.rate_limit(nil).remaining

          limiter.track(response_with("X-RateLimit-Remaining" => "1")) # another process spent some

          assert_equal 1, limiter.rate_limit(nil).remaining
        end

        it "starts a fresh window when the API's reset is beyond the local window" do
          limiter, time = limiter_with(FixedWindow.new(limit: 10, window: 60, headers: true))
          3.times { limiter.throttle }
          time.advance(50)
          limiter.track(response_with("X-RateLimit-Remaining" => "9", "X-RateLimit-Reset" => (time.now + 50).to_i.to_s))

          assert_equal 9, limiter.rate_limit(nil).remaining
          assert_in_delta time.now + 50, limiter.rate_limit(nil).reset, 1
        end

        it "rolls the window before syncing so a late response cannot revive a spent window" do
          limiter, time = limiter_with(FixedWindow.new(limit: 2, window: 60, headers: true))
          2.times { limiter.throttle }
          time.advance(61)
          limiter.track(response_with("X-RateLimit-Remaining" => "0"))

          assert_equal 0, limiter.rate_limit(nil).remaining # the new window's budget, then the report
          time.advance(60)

          assert_equal 2, limiter.rate_limit(nil).remaining
        end

        it "does not trust a non-finite or far-future reset" do
          limiter, time = limiter_with(FixedWindow.new(limit: 1, window: 60, headers: true))
          limiter.throttle
          limiter.track(response_with("X-RateLimit-Remaining" => "0", "X-RateLimit-Reset" => "9" * 400))

          assert_in_delta 60, limiter.throttle, 0.001

          limiter.track(response_with("X-RateLimit-Remaining" => "0", "X-RateLimit-Reset" => (time.now + 86_400).to_i.to_s))

          assert_in_delta 60, limiter.throttle, 0.001
        end
      end

      describe SlidingWindow do
        it "admits limit requests in any trailing window" do
          limiter, time = limiter_with(SlidingWindow.new(limit: 3, window: 10))

          limiter.throttle
          time.advance(4)
          2.times { limiter.throttle }

          assert_equal 0, limiter.rate_limit(nil).remaining
          assert_in_delta 6, limiter.throttle, 0.001 # until the first request ages out
          assert_equal [6.0], time.sleeps
          time.advance(4)

          assert_equal 2, limiter.rate_limit(nil).remaining   # the two at t+4 aged out too
        end
      end

      describe TokenBucket do
        it "allows a burst up to capacity, then paces at the refill rate" do
          limiter, time = limiter_with(TokenBucket.new(capacity: 3, refill_rate: 2))

          3.times { assert_equal 0, limiter.throttle }
          assert_equal 0, limiter.rate_limit(nil).remaining
          assert_in_delta 0.5, limiter.throttle, 0.001
          assert_equal [0.5], time.sleeps

          time.advance(10)

          assert_equal 3, limiter.rate_limit(nil).remaining   # refilled to capacity, no more
        end
      end

      describe LeakyBucket do
        it "fills to capacity, then waits for the bucket to drain" do
          limiter, time = limiter_with(LeakyBucket.new(capacity: 2, leak_rate: 1))

          2.times { assert_equal 0, limiter.throttle }
          assert_equal 0, limiter.rate_limit(nil).remaining
          assert_in_delta 1, limiter.throttle, 0.001
          assert_equal [1.0], time.sleeps

          time.advance(5)

          assert_equal 2, limiter.rate_limit(nil).remaining
          assert_nil limiter.rate_limit(nil).reset
        end
      end

      describe "the strategy macro" do
        it "configures instances of the limiter class and its subclasses" do
          klass = Class.new(Resteze::RateLimiter) { strategy :token_bucket, capacity: 5, refill_rate: 1 }

          assert_equal [TokenBucket, { capacity: 5, refill_rate: 1 }], klass.strategy
          assert_equal klass.strategy, Class.new(klass).strategy
          assert_kind_of TokenBucket, klass.new.strategy
          assert_kind_of TokenBucket, Class.new(klass).new.strategy
          assert_equal 5, klass.new.strategy.capacity
        end

        it "rejects limiter options given without a strategy" do
          assert_raises(ArgumentError) { Class.new(Resteze::RateLimiter) { strategy(on_wait: :raise) } }
          assert_raises(ArgumentError) { Class.new(Resteze::RateLimiter) { strategy(max_wait: 5) } }
        end

        it "takes max_wait from the macro, the constructor or the default" do
          klass = Class.new(Resteze::RateLimiter) { strategy :token_bucket, capacity: 1, refill_rate: 1, max_wait: 5 }

          assert_in_delta 5.0, klass.max_wait
          assert_in_delta 5.0, Class.new(klass).new.max_wait
          assert_equal Resteze::RateLimiter::DEFAULT_MAX_WAIT, Resteze::RateLimiter.new.max_wait
          assert_raises(ArgumentError) { Resteze::RateLimiter.new(max_wait: 0) }
        end

        it "clamps every wait to max_wait, including non-finite and absurd ones" do
          sleeps  = []
          limiter = Resteze::RateLimiter.new(max_wait: 10, sleeper: ->(seconds) { sleeps << seconds })

          assert_in_delta 10.0, limiter.wait(Float::INFINITY)
          assert_in_delta 10.0, limiter.wait(Float::NAN)
          assert_in_delta 10.0, limiter.wait(10**400)
          assert_in_delta 0.0,  limiter.wait(-5)
          assert_in_delta 2.5,  limiter.wait(2.5)
          assert_equal [10.0, 10.0, 10.0, 2.5], sleeps
        end

        it "accepts a custom Strategy class" do
          custom = Class.new(Strategy) do
            def initialize(wait:)
              super()
              @wait = wait
            end

            def acquire(state, _now)
              state[:calls] = state.fetch(:calls, 0) + 1
              state[:calls].odd? ? @wait : 0
            end
          end
          klass = Class.new(Resteze::RateLimiter) { strategy custom, wait: 2 }
          time = FakeTime.new
          limiter = klass.new(clock: time.clock, sleeper: time.sleeper)

          assert_equal 2, limiter.throttle
          assert_equal [2.0], time.sleeps
        end

        it "raises instead of waiting with on_wait: :raise, carrying the wait in retry_after" do
          klass = Class.new(Resteze::RateLimiter) { strategy :fixed_window, limit: 1, window: 45, on_wait: :raise }
          time = FakeTime.new
          limiter = klass.new(clock: time.clock, sleeper: time.sleeper)

          assert_equal 0, limiter.throttle
          error = assert_raises(Resteze::RateLimitError) { limiter.throttle }

          assert_equal 45, error.retry_after
          assert_nil error.http_status
          assert_empty time.sleeps
        end

        it "inherits on_wait from the limiter class" do
          klass = Class.new(Resteze::RateLimiter) { strategy :fixed_window, limit: 1, window: 45, on_wait: :raise }

          assert_equal :raise, klass.on_wait
          assert_equal :raise, klass.new.on_wait
          assert_equal :raise, Class.new(klass).on_wait
        end

        it "takes on_wait from the constructor too, and rejects other values" do
          assert_equal :raise, Resteze::RateLimiter.new(on_wait: :raise).on_wait
          assert_equal :sleep, Resteze::RateLimiter.new.on_wait
          assert_raises(ArgumentError) { Resteze::RateLimiter.new(on_wait: :enqueue) }
          assert_raises(ArgumentError) { Class.new(Resteze::RateLimiter) { strategy :token_bucket, capacity: 1, refill_rate: 1, on_wait: :block } }
        end

        it "leaves the limiter a no-op without one" do
          limiter = Resteze::RateLimiter.new

          assert_nil limiter.strategy
          assert_nil limiter.before_request(:get, "/")
          assert_nil limiter.rate_limit(nil)
        end
      end
    end
  end
end
