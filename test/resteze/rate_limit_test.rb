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
        assert_nil Resteze::RateLimit.from_headers("Content-Type" => "application/json")
      end

      it "leaves absent or non-numeric values nil" do
        rate_limit = Resteze::RateLimit.from_headers("X-RateLimit-Remaining" => "0", "X-RateLimit-Reset" => "soon")

        assert_nil rate_limit.limit
        assert_equal 0, rate_limit.remaining
        assert_nil rate_limit.reset
      end

      it "accepts custom header names" do
        names = { limit: "RateLimit-Limit", remaining: "RateLimit-Remaining", reset: "RateLimit-Reset" }
        rate_limit = Resteze::RateLimit.from_headers({ "RateLimit-Remaining" => "7" }, names)

        assert_equal 7, rate_limit.remaining
        assert_nil Resteze::RateLimit.from_headers(HEADERS, names)
      end

      it "falls back to the defaults when names are nil" do
        assert_equal 249_990, Resteze::RateLimit.from_headers(HEADERS, nil).remaining
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

    describe "Response#rate_limit" do
      subject { AcmeApi::Client.new }

      it "is built from the response headers" do
        stub_request(:get, api_url("/widgets/1")).to_return(body: "{}", headers: HEADERS)

        rate_limit = subject.execute_request(:get, "/widgets/1").rate_limit

        assert_equal 249_990, rate_limit.remaining
      end

      it "is nil when the API sends no rate-limit headers" do
        stub_request(:get, api_url("/widgets/1")).to_return(body: "{}")

        assert_nil subject.execute_request(:get, "/widgets/1").rate_limit
      end

      it "uses the module's configured header names" do
        AcmeApi.rate_limit_headers = { limit: "L", remaining: "R", reset: "S" }
        stub_request(:get, api_url("/widgets/1")).to_return(body: "{}", headers: { "R" => "5" }.merge(HEADERS))

        rate_limit = subject.execute_request(:get, "/widgets/1").rate_limit

        assert_equal 5, rate_limit.remaining
        assert_nil rate_limit.limit
      ensure
        AcmeApi.rate_limit_headers = Resteze::RateLimit::DEFAULT_HEADERS
      end
    end

    describe "Error#rate_limit" do
      it "is built from the error's headers" do
        stub_request(:get, api_url("/widgets/1"))
          .to_return(status: 429, headers: HEADERS.merge("X-RateLimit-Remaining" => "0", "Retry-After" => "12"))

        error = assert_raises(AcmeApi::RateLimitError) { AcmeApi::Client.new.execute_request(:get, "/widgets/1") }

        assert_predicate error.rate_limit, :exhausted?
        assert_equal 12, error.retry_after
      end

      it "is nil without headers" do
        assert_nil AcmeApi::ApiError.new("boom").rate_limit
      end
    end

    describe "configuration" do
      it "defaults rate_limit_headers to the X-RateLimit names" do
        assert_equal Resteze::RateLimit::DEFAULT_HEADERS, AcmeApi.rate_limit_headers
      end
    end
  end
end
