require "test_helper"

module Resteze
  class ErrorsTest < Minitest::Spec
    def self.must_support_to_s(message = "message", *)
      describe "#to_s" do
        it "should convert to string" do
          e = subject.new(message, *)

          assert_equal message, e.to_s

          e = subject.new(message, *, http_status: 200)

          assert_equal "HTTP 200: #{message}", e.to_s
        end
      end
    end

    describe "Resteze::Error" do
      subject { Resteze::Error }
      must_support_to_s
    end

    describe "Resteze::InvalidRequestError" do
      subject { Resteze::InvalidRequestError }
      must_support_to_s("message", "id")
    end

    describe "Resteze::AuthenticationError" do
      subject { Resteze::AuthenticationError }
      must_support_to_s
    end

    describe "Resteze::ApiConnectionError" do
      subject { Resteze::ApiConnectionError }
      must_support_to_s
    end

    describe "Resteze::ApiError" do
      subject { Resteze::ApiError }
      must_support_to_s
    end

    describe "AcmeApi::Error" do
      subject { AcmeApi::Error }
      must_support_to_s
    end

    describe "AcmeApi::InvalidRequestError" do
      subject { AcmeApi::InvalidRequestError }
      must_support_to_s("message", "id")
    end

    describe "AcmeApi::AuthenticationError" do
      subject { AcmeApi::AuthenticationError }
      must_support_to_s
    end

    describe "AcmeApi::ApiConnectionError" do
      subject { AcmeApi::ApiConnectionError }
      must_support_to_s
    end

    describe "AcmeApi::ApiError" do
      subject { AcmeApi::ApiError }
      must_support_to_s
    end

    describe "AcmeApi::RateLimitError" do
      subject { AcmeApi::RateLimitError }
      must_support_to_s
    end

    describe "namespacing" do
      it "defines every error type as a subclass of the module's own Error" do
        Resteze::Errors::TYPES.each_key do |name|
          assert AcmeApi.const_defined?(name, false), "AcmeApi::#{name} should be defined on AcmeApi itself"
          assert_operator AcmeApi.const_get(name), :<, AcmeApi::Error
          assert_operator Resteze.const_get(name), :<, Resteze::Error
        end
      end

      it "keeps the hierarchy rooted in Resteze::Error" do
        assert_operator AcmeApi::Error,    :<, Resteze::Error
        assert_operator AcmeApi::ApiError, :<, Resteze::Error
      end

      it "isolates errors between API modules" do
        refute_equal AcmeApi::ApiError, VerbApi::ApiError
        refute_operator AcmeApi::ApiError, :<, VerbApi::Error
      end

      it "includes the 404, 409 and 422 classes" do
        %i[ResourceNotFound ConflictError UnprocessableEntityError].each do |name|
          assert_operator AcmeApi.const_get(name), :<, AcmeApi::Error
          refute_operator AcmeApi.const_get(name), :<, Faraday::Error
        end
      end

      it "keeps type behaviour on the namespaced classes" do
        assert_equal "id", AcmeApi::InvalidRequestError.new("message", "id").param
        assert_respond_to AcmeApi::RateLimitError.new("slow"), :retry_after
      end
    end

    describe ".from_faraday" do
      def faraday_error(klass = Faraday::ServerError, status: 500, body: '{"message":"down"}', headers: {})
        klass.new("boom", { status:, body:, headers: Faraday::Utils::Headers.new(headers) })
      end

      it "copies the response onto the error" do
        error = Resteze::ApiError.from_faraday(faraday_error(headers: { "Request-Id" => "req_9" }))

        assert_equal "boom",               error.message
        assert_equal 500,                  error.http_status
        assert_equal '{"message":"down"}', error.http_body
        assert_equal "req_9",              error.http_headers["Request-Id"]
        assert_equal({ message: "down" },  error.json_body)
        assert_equal 500,                  error.response[:status]
      end

      it "accepts an explicit message" do
        error = Resteze::ApiError.from_faraday(faraday_error, "custom")

        assert_equal "custom", error.message
      end

      it "exposes Faraday-style readers alongside the http_ ones" do
        error = Resteze::ApiError.from_faraday(faraday_error(headers: { "Request-Id" => "req_9" }))

        assert_equal error.http_status,  error.response_status
        assert_equal error.http_body,    error.response_body
        assert_equal error.http_headers, error.response_headers
      end

      it "tolerates an error with no response" do
        error = Resteze::ApiConnectionError.from_faraday(Faraday::ConnectionFailed.new("refused"))

        assert_equal "refused", error.message
        assert_nil error.http_status
        assert_nil error.json_body
        assert_empty error.http_headers
      end

      it "builds an InvalidRequestError with no param" do
        error = Resteze::InvalidRequestError.from_faraday(faraday_error(Faraday::BadRequestError, status: 400))

        assert_equal 400, error.http_status
        assert_nil error.param
      end
    end

    describe ".from_response" do
      def response(data, status: 201, body: "{}", headers: { "Request-Id" => "req_r" })
        Resteze::Response.new.tap do |r|
          r.data = data
          r.http_status = status
          r.http_body = body
          r.http_headers = headers
        end
      end

      it "copies the response onto the error" do
        error = Resteze::ApiError.from_response(response({ message: "nope" }), "failed")

        assert_equal "failed",           error.message
        assert_equal 201,                error.http_status
        assert_equal "{}",               error.http_body
        assert_equal "req_r",            error.http_headers["Request-Id"]
        assert_equal({ message: "nope" }, error.json_body)
        assert_kind_of Resteze::Response, error.response
      end

      it "leaves json_body nil for a non-structured body" do
        assert_nil Resteze::ApiError.from_response(response("plain text")).json_body
      end

      it "builds an InvalidRequestError with no param" do
        error = Resteze::InvalidRequestError.from_response(response({}), "bad")

        assert_equal "bad", error.message
        assert_nil error.param
      end
    end

    describe "RateLimitError#retry_after" do
      def rate_limit_error(headers)
        Resteze::RateLimitError.new("slow down", http_status: 429, http_headers: headers)
      end

      it "returns the Retry-After header as integer seconds" do
        assert_equal 30, rate_limit_error("Retry-After" => "30").retry_after
      end

      it "matches the header name case-insensitively" do
        assert_equal 30, rate_limit_error("retry-after" => "30").retry_after
      end

      it "converts an HTTP-date Retry-After into seconds from now" do
        retry_after = rate_limit_error("Retry-After" => (Time.now + 120).httpdate).retry_after

        assert_in_delta 120, retry_after, 2
      end

      it "is nil when the header is missing or unparseable" do
        assert_nil rate_limit_error({}).retry_after
        assert_nil rate_limit_error("Retry-After" => "soon").retry_after
      end

      it "prefers a retry_after given at construction over the header" do
        error = Resteze::RateLimitError.new("wait", retry_after: 7, http_headers: { "Retry-After" => "30" })

        assert_equal 7, error.retry_after
        assert_equal 30, Resteze::RateLimitError.new("wait", http_headers: { "Retry-After" => "30" }).retry_after
      end
    end
  end
end
