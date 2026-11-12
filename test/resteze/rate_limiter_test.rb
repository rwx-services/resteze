require "test_helper"

module Resteze
  class RateLimiterTest < Minitest::Spec
    HEADERS = { "X-RateLimit-Limit" => "100", "X-RateLimit-Remaining" => "42", "X-RateLimit-Reset" => "1762987200" }.freeze
    URL = "http://body.example.com/users/1".freeze
    SUCCESS = '{"message":"success"}'.freeze

    before do
      BodyApi.rate_limiter = BodyApi::RateLimiter.new
    end

    after do
      BodyApi.rate_limiter = nil
    end

    def capture_events(event_name)
      events = []
      subscriber = ActiveSupport::Notifications.subscribe(event_name) do |*args|
        events << ActiveSupport::Notifications::Event.new(*args)
      end
      yield
      events
    ensure
      ActiveSupport::Notifications.unsubscribe(subscriber)
    end

    describe "the interface" do
      subject { Resteze::RateLimiter.new }

      it "is a no-op by default" do
        error = Resteze::RateLimitError.new("slow", http_headers: { "Retry-After" => "3" })

        assert_nil subject.before_request(:get, "/x", params: {}, headers: {})
        assert_nil subject.track(Resteze::Response.new)
        assert_nil subject.rate_limit(Resteze::Response.new)
        refute subject.retry?(error, 1)
        assert_equal 3, subject.retry_after(error)
      end

      it "gives every API module its own subclass" do
        assert_operator AcmeApi::RateLimiter, :<, Resteze::RateLimiter
        refute_equal AcmeApi::RateLimiter, BodyApi::RateLimiter
      end

      it "is instantiated once per module and can be replaced" do
        assert_kind_of AcmeApi::RateLimiter, AcmeApi.rate_limiter
        assert_same AcmeApi.rate_limiter, AcmeApi.rate_limiter

        custom = Resteze::RateLimiter.new
        AcmeApi.rate_limiter = custom

        assert_same custom, AcmeApi.rate_limiter
      ensure
        AcmeApi.rate_limiter = nil
      end
    end

    describe "state" do
      subject { Resteze::RateLimiter.new }

      it "starts empty and returns deep snapshots" do
        assert_empty subject.state

        subject.update_state(remaining: 5, times: [1])
        snapshot = subject.state
        snapshot[:remaining] = 0
        snapshot[:times] << 2

        assert_equal 5,   subject.state[:remaining]
        assert_equal [1], subject.state[:times]
      end

      it "allows read-modify-write inside synchronize, re-entrantly" do
        subject.update_state(count: 0)
        subject.synchronize do |state|
          state[:count] += 1
          subject.update_state(seen: subject.state[:count])
        end

        assert_equal({ count: 1, seen: 1 }, subject.state)
      end

      it "is safe to update from many threads" do
        subject.update_state(count: 0)
        Array.new(8) do
          Thread.new { 250.times { subject.synchronize { |state| state[:count] += 1 } } }
        end.each(&:join)

        assert_equal 2000, subject.state[:count]
      end
    end

    describe "the request lifecycle" do
      it "tracks every response and exposes rate_limit" do
        stub_request(:get, URL).to_return(body: SUCCESS, headers: HEADERS)

        response = BodyApi::Client.new.execute_request(:get, "/users/1")

        assert_equal 42, response.rate_limit.remaining
        assert_equal({ requests: 1, remaining: 42, reset: 1_762_987_200 }, BodyApi.rate_limiter.state)
      end

      it "tracks errors too" do
        stub_request(:get, URL).to_return(status: 503, headers: HEADERS.merge("X-RateLimit-Remaining" => "7"))

        error = assert_raises(BodyApi::ApiError) { BodyApi::Client.new.execute_request(:get, "/users/1") }

        assert_equal 7, error.rate_limit.remaining
        assert_equal 7, BodyApi.rate_limiter.state[:remaining]
      end

      it "retries a 429 when the limiter says so, instrumenting each attempt" do
        stub_request(:get, URL)
          .to_return(status: 429, headers: { "Retry-After" => "0" })
          .then.to_return(body: '{"message":"success","ok":true}', headers: HEADERS)

        events = capture_events("request.body_api") do
          assert BodyApi::Client.new.execute_request(:get, "/users/1").data[:ok]
        end

        assert_equal 2, events.size
        assert_equal([429, 200], events.map { |event| event.payload[:status] })
        assert_equal 2, BodyApi.rate_limiter.state[:requests]
      end

      it "gives up when the limiter stops retrying" do
        stub_request(:get, URL).to_return(status: 429, headers: { "Retry-After" => "0" })

        assert_raises(BodyApi::RateLimitError) { BodyApi::Client.new.execute_request(:get, "/users/1") }
        assert_requested :get, URL, times: 3
      end

      it "waits retry_after seconds between attempts through the limiter's sleeper" do
        sleeps = []
        BodyApi.rate_limiter = BodyApi::RateLimiter.new(sleeper: ->(seconds) { sleeps << seconds })
        stub_request(:get, URL).to_return(status: 429, headers: { "Retry-After" => "2" }).then.to_return(body: SUCCESS)

        BodyApi::Client.new.execute_request(:get, "/users/1")

        assert_equal [2.0], sleeps
      end

      it "clamps a retry wait to max_wait" do
        sleeps = []
        BodyApi.rate_limiter = BodyApi::RateLimiter.new(max_wait: 3, sleeper: ->(seconds) { sleeps << seconds })
        stub_request(:get, URL).to_return(status: 429, headers: { "Retry-After" => "9" * 400 }).then.to_return(body: SUCCESS)

        BodyApi::Client.new.execute_request(:get, "/users/1")

        assert_equal [3.0], sleeps
      end

      it "raises the 429 itself instead of sleeping before a retry under on_wait: :raise" do
        sleeps = []
        BodyApi.rate_limiter = BodyApi::RateLimiter.new(on_wait: :raise, sleeper: ->(seconds) { sleeps << seconds })
        stub_request(:get, URL).to_return(status: 429, headers: { "Retry-After" => "7" })

        error = assert_raises(BodyApi::RateLimitError) { BodyApi::Client.new.execute_request(:get, "/users/1") }

        assert_equal 429, error.http_status
        assert_equal 7,   error.retry_after
        assert_empty sleeps
        assert_requested :get, URL, times: 1
      end

      it "raises the module's error even from a replacement limiter of another class" do
        strategy = Resteze::RateLimiter::FixedWindow.new(limit: 1, window: 60)
        BodyApi.rate_limiter = Resteze::RateLimiter.new(strategy:, on_wait: :raise)
        stub_request(:get, URL).to_return(body: SUCCESS)

        BodyApi::Client.new.execute_request(:get, "/users/1")

        assert_raises(BodyApi::RateLimitError) { BodyApi::Client.new.execute_request(:get, "/users/1") }
        assert_equal BodyApi, BodyApi.rate_limiter.api_module
      end

      it "never retries with the default no-op limiter" do
        stub_request(:get, api_url("/widgets/1")).to_return(status: 429)

        assert_raises(AcmeApi::RateLimitError) { AcmeApi::Client.new.execute_request(:get, "/widgets/1") }
        assert_requested :get, api_url("/widgets/1"), times: 1
      end

      it "throttles with a configured strategy, instrumenting the wait as part of the request" do
        now    = Time.now.to_f
        sleeps = []
        sleeper = lambda do |seconds|
          sleeps << seconds
          now += seconds
        end
        BodyApi.rate_limiter = Class.new(BodyApi::RateLimiter) { strategy :fixed_window, limit: 1, window: 30 }
                                    .new(clock: -> { now }, sleeper:)
        stub_request(:get, URL).to_return(body: SUCCESS)

        BodyApi::Client.new.execute_request(:get, "/users/1")
        BodyApi::Client.new.execute_request(:get, "/users/1")

        assert_equal 1, sleeps.size
        assert_in_delta 30, sleeps.first, 1
        assert_requested :get, URL, times: 2
      end

      it "raises the module's RateLimitError under on_wait: :raise without sending or retrying" do
        BodyApi.rate_limiter = Class.new(BodyApi::RateLimiter) do
          strategy :fixed_window, limit: 1, window: 30, on_wait: :raise
        end.new
        stub_request(:get, URL).to_return(body: SUCCESS)

        BodyApi::Client.new.execute_request(:get, "/users/1")
        error = assert_raises(BodyApi::RateLimitError) { BodyApi::Client.new.execute_request(:get, "/users/1") }

        assert_equal 30, error.retry_after
        assert_nil error.http_status
        assert_requested :get, URL, times: 1 # the fixture's retry? would have said yes; refusals never retry
      end

      it "lets before_request refuse a request before it is sent" do
        BodyApi.rate_limiter = Class.new(BodyApi::RateLimiter) do
          def before_request(*, **)
            raise BodyApi::RateLimitError, "local budget exhausted"
          end
        end.new
        stub_request(:get, URL)

        error = assert_raises(BodyApi::RateLimitError) { BodyApi::Client.new.execute_request(:get, "/users/1") }

        assert_equal "local budget exhausted", error.message
        assert_not_requested :get, URL
      end
    end
  end
end
