require "test_helper"

module Resteze
  module Middleware
    class RaiseErrorTest < Minitest::Spec
      subject { AcmeApi::Client.new }

      def stub_status(status, body: '{"message":"nope"}', headers: {})
        headers = { "Content-Type" => "application/json", "Request-Id" => "req_1" }.merge(headers)
        stub_request(:get, api_url("/widgets/1")).to_return(status:, body:, headers:)
      end

      def request_error(klass)
        assert_raises(klass) { subject.execute_request(:get, "/widgets/1") }
      end

      describe "status mapping" do
        it "raises InvalidRequestError for a 400" do
          stub_status(400)
          error = request_error(AcmeApi::InvalidRequestError)

          assert_equal 400, error.http_status
          assert_nil error.param
        end

        it "raises AuthenticationError for a 401" do
          stub_status(401)

          assert_equal 401, request_error(AcmeApi::AuthenticationError).http_status
        end

        it "raises AuthenticationError for a 403" do
          stub_status(403)

          assert_equal 403, request_error(AcmeApi::AuthenticationError).http_status
        end

        it "raises RateLimitError for a 429 with retry_after" do
          stub_status(429, headers: { "Retry-After" => "7" })
          error = request_error(AcmeApi::RateLimitError)

          assert_equal 429, error.http_status
          assert_equal 7,   error.retry_after
        end

        it "raises ApiError for any other 4xx" do
          stub_status(418)

          assert_equal 418, request_error(AcmeApi::ApiError).http_status
        end

        it "raises ApiError for a 5xx" do
          stub_status(503)

          assert_equal 503, request_error(AcmeApi::ApiError).http_status
        end

        it "raises namespaced Error subclasses for 404, 409 and 422" do
          { 404 => AcmeApi::ResourceNotFound, 409 => AcmeApi::ConflictError,
            422 => AcmeApi::UnprocessableEntityError }.each do |status, klass|
            stub_status(status)
            error = request_error(klass)

            assert_kind_of AcmeApi::Error, error
            assert_equal status, error.http_status
            assert_kind_of Faraday::ClientError, error.cause
          end
        end

        it "keeps the Faraday-style readers on those errors" do
          stub_status(404, body: '{"message":"gone"}')
          error = request_error(AcmeApi::ResourceNotFound)

          assert_equal 404,                  error.response_status
          assert_equal '{"message":"gone"}', error.response_body
          assert_equal "req_1",              error.response_headers["Request-Id"]
          assert_equal 404,                  error.response[:status]
        end

        it "lets rescue AcmeApi::Error catch a 404" do
          stub_status(404)

          assert_raises(AcmeApi::Error) { subject.execute_request(:get, "/widgets/1") }
        end
      end

      describe "connection failures" do
        it "raises ApiConnectionError when the connection is refused" do
          stub_request(:get, api_url("/widgets/1")).to_raise(Errno::ECONNREFUSED)
          error = request_error(AcmeApi::ApiConnectionError)

          assert_nil error.http_status
          assert_kind_of Faraday::ConnectionFailed, error.cause
        end

        it "raises ApiConnectionError when the request times out" do
          stub_request(:get, api_url("/widgets/1")).to_timeout

          request_error(AcmeApi::ApiConnectionError)
        end
      end

      describe "error attributes" do
        it "carries the response body, headers, parsed JSON and Faraday response" do
          stub_status(503, body: '{"message":"down","errors":["db"]}')
          error = request_error(AcmeApi::ApiError)

          assert_equal '{"message":"down","errors":["db"]}', error.http_body
          assert_equal "req_1", error.http_headers["Request-Id"]
          assert_equal({ message: "down", errors: ["db"] }, error.json_body)
          assert_equal 503, error.response[:status]
          assert_kind_of AcmeApi::Error, error
          assert_kind_of Faraday::ServerError, error.cause
        end

        it "leaves json_body nil when the body is not JSON" do
          stub_status(500, body: "<html>oops</html>", headers: { "Content-Type" => "text/html" })

          assert_nil request_error(AcmeApi::ApiError).json_body
        end

        it "is rescuable as the namespaced base Error" do
          stub_status(500)

          assert_raises(AcmeApi::Error) { subject.execute_request(:get, "/widgets/1") }
        end

        it "does not leak across API modules" do
          stub_status(500)
          error = request_error(AcmeApi::ApiError)

          refute_kind_of VerbApi::Error, error
        end
      end
    end
  end
end
