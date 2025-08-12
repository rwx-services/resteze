require "test_helper"

module Resteze
  class ResponseTest < Minitest::Spec
    subject { Resteze::Response }

    describe ".from_faraday_response" do
      it "should convert to Response object" do
        faraday_response = Faraday::Response.new(
          Faraday::Env.from(
            status: 200,
            body: '{"foo": "bar"}',
            response_headers: { "Request-Id" => "request-id" }
          )
        )

        response = subject.from_faraday_response(faraday_response)

        assert_equal({ foo: "bar" },                   response.data)
        assert_equal('{"foo": "bar"}',                 response.http_body)
        assert_equal({ "Request-Id" => "request-id" }, response.http_headers)
        assert_equal(200,                              response.http_status)
        assert_equal("request-id",                     response.request_id)
      end
    end

    describe ".parse_body" do
      it "should parse JSON if no content-type" do
        assert_equal({ foo: "bar" }, subject.parse_body('{"foo": "bar"}'))
      end

      it "should parse JSON if explicit JSON content-type" do
        assert_equal({ foo: "bar" },
                     subject.parse_body('{"foo": "bar"}', headers: { "content-type" => "application/json" }))
        assert_equal({ foo: "bar" },
                     subject.parse_body('{"foo": "bar"}',
                                        headers: { "content-type" => "application/json; charset=utf-8" }))
      end

      it "should parse XML if XML content-type" do
        assert_equal({ foo: "bar" },
                     subject.parse_body("<foo>bar</foo>", headers: { "content-type" => "application/xml" }))
      end

      it "should leave body alone if unrecognized content-type" do
        assert_equal("some content", subject.parse_body("some content", headers: { "content-type" => "text/plain" }))
      end
    end

    describe ".mime_type" do
      it "should return JSON if no content-type" do
        assert_equal Mime::Type.lookup("application/json"), subject.mime_type
        assert_equal Mime::Type.lookup("application/json"), subject.mime_type(foo: "bar")
        assert_equal Mime::Type.lookup("application/json"), subject.mime_type("content-type" => "")
        assert_equal Mime::Type.lookup("application/json"), subject.mime_type("content-type" => " ; ")
      end

      it "should return JSON if JSON content-type" do
        assert_equal Mime::Type.lookup("application/json"), subject.mime_type("content-type" => "application/json")
        assert_equal Mime::Type.lookup("application/json"),
                     subject.mime_type("content-type" => "application/json; charset=utf-8")
        assert_equal Mime::Type.lookup("application/json"),
                     subject.mime_type("content-type" => "  application/json  ; charset=utf-8  ")
      end

      it "should return XML if XML content-type" do
        assert_equal Mime::Type.lookup("application/xml"), subject.mime_type("content-type" => "application/xml")
        assert_equal Mime::Type.lookup("application/xml"),
                     subject.mime_type("content-type" => "application/xml; charset=utf-8")
        assert_equal Mime::Type.lookup("application/xml"), subject.mime_type("content-type" => "text/xml")
        assert_equal Mime::Type.lookup("application/xml"), subject.mime_type("content-type" => "application/x-xml")
      end

      it "should return PDF if PDF content-type" do
        assert_equal Mime::Type.lookup("application/pdf"), subject.mime_type("content-type" => "application/pdf")
      end

      it "should return HTML if HTML content-type" do
        assert_equal Mime::Type.lookup("text/html"), subject.mime_type("content-type" => "text/html; charset=utf8")
      end
    end
  end
end
