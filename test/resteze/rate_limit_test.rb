require "test_helper"

module Resteze
  class RateLimitTest < Minitest::Spec
    HEADERS = { "X-RateLimit-Limit" => "250000", "X-RateLimit-Remaining" => "249990",
                "X-RateLimit-Reset" => "1762987200" }.freeze

    describe ".from_headers" do
      it "reads the X-RateLimit headers by default" do
        rate_limit = Resteze::RateLimit.from_headers(HEADERS)

        assert_equal 250_000,       rate_limit.limit
        assert_equal 249_990,       rate_limit.remaining
        assert_equal 1_762_987_200, rate_limit.reset
      end

      it "matches header names case-insensitively" do
        rate_limit = Resteze::RateLimit.from_headers("x-ratelimit-remaining" => "3")

        assert_equal 3, rate_limit.remaining
      end

      it "is nil when none of the headers are present" do
        assert_nil Resteze::RateLimit.from_headers({})
        assert_nil Resteze::RateLimit.from_headers(nil)
        assert_nil Resteze::RateLimit.from_headers("Content-Type" => "application/json")
      end

      it "leaves absent or non-numeric values nil" do
        rate_limit = Resteze::RateLimit.from_headers("X-RateLimit-Remaining" => "0", "X-RateLimit-Reset" => "soon")

        assert_nil rate_limit.limit
        assert_equal 0, rate_limit.remaining
        assert_nil rate_limit.reset
      end

      it "accepts other header names, keeping the defaults for names not given" do
        rate_limit = Resteze::RateLimit.from_headers({ "RateLimit-Remaining" => "7", "X-RateLimit-Limit" => "9" },
                                                     remaining: "RateLimit-Remaining")

        assert_equal 7, rate_limit.remaining
        assert_equal 9, rate_limit.limit
      end
    end

    describe "#exhausted?" do
      it "is true only when remaining is zero" do
        assert_predicate Resteze::RateLimit.new(remaining: 0), :exhausted?
        refute_predicate Resteze::RateLimit.new(remaining: 1), :exhausted?
        refute_predicate Resteze::RateLimit.new(limit: 10), :exhausted?
      end
    end

    describe "#to_h" do
      it "returns the three values" do
        assert_equal({ limit: 1, remaining: 2, reset: 3 }, Resteze::RateLimit.new(limit: 1, remaining: 2, reset: 3).to_h)
      end
    end

    describe "rate_limit readers" do
      it "are nil with the default no-op limiter, even when X-RateLimit headers are present" do
        stub_request(:get, api_url("/widgets/1")).to_return(body: "{}", headers: HEADERS)

        assert_nil AcmeApi::Client.new.execute_request(:get, "/widgets/1").rate_limit
        assert_nil AcmeApi::ApiError.new("boom").rate_limit
        assert_nil Resteze::Response.new.rate_limit
      end

      it "ask the module's limiter, on responses" do
        stub_request(:get, "http://body.example.com/users/1")
          .to_return(body: '{"message":"success"}', headers: HEADERS)

        rate_limit = BodyApi::Client.new.execute_request(:get, "/users/1").rate_limit

        assert_kind_of Resteze::RateLimit, rate_limit
        assert_equal 249_990, rate_limit.remaining
      end

      it "ask the module's limiter, on errors" do
        BodyApi.rate_limiter = Class.new(BodyApi::RateLimiter) { def retry?(*) = false }.new
        stub_request(:get, "http://body.example.com/users/1")
          .to_return(status: 429, headers: HEADERS.merge("X-RateLimit-Remaining" => "0", "Retry-After" => "12"))

        error = assert_raises(BodyApi::RateLimitError) { BodyApi::Client.new.execute_request(:get, "/users/1") }

        assert_predicate error.rate_limit, :exhausted?
        assert_equal 12, error.retry_after
      ensure
        BodyApi.rate_limiter = nil
      end
    end

    describe "RateLimitError#retry_after" do
      it "reads the HTTP Retry-After header" do
        assert_equal 4, AcmeApi::RateLimitError.new("slow", http_headers: { "retry-after" => "4" }).retry_after
      end

      it "can be redefined per module" do
        klass = Class.new(AcmeApi::RateLimitError) do
          def retry_after
            header("X-Retry-In")&.to_i || super
          end
        end

        assert_equal 9, klass.new("slow", http_headers: { "X-Retry-In" => "9", "Retry-After" => "99" }).retry_after
        assert_equal 99, klass.new("slow", http_headers: { "Retry-After" => "99" }).retry_after
      end
    end
  end
end
