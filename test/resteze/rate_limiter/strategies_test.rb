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
          assert_kind_of TokenBucket, klass.new.strategy
          assert_kind_of TokenBucket, Class.new(klass).new.strategy
          assert_equal 5, klass.new.strategy.capacity
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
