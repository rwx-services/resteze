require "test_helper"

module Resteze
  class ResultTest < Minitest::Spec
    def response_with(data, status: 200)
      AcmeApi::Response.new.tap do |r|
        r.data = data
        r.http_status = status
      end
    end

    describe ".from_response" do
      it "exposes hash data with dot and key access" do
        result = AcmeApi::Result.from_response(response_with({ message: "success", counts: { events: 2 } }))

        assert_equal "success", result.message
        assert_equal "success", result[:message]
        assert_equal 2, result.counts.events
      end

      it "keeps the response" do
        response = response_with({ message: "success" })
        result = AcmeApi::Result.from_response(response)

        assert_same response, result.http_response
        assert_equal 200, result.http_response.http_status
      end

      it "is empty for a non-hash body and never raises" do
        empty = AcmeApi::Result.from_response(response_with("", status: 204))
        array = AcmeApi::Result.from_response(response_with([{ id: 1 }]))

        assert_empty empty
        assert_equal "", empty.http_response.data
        assert_empty array
        assert_equal [{ id: 1 }], array.http_response.data
      end
    end

    it "is namespaced per API module" do
      assert_operator AcmeApi::Result, :<, Resteze::Result
      assert_equal AcmeApi, AcmeApi::Result.api_module
    end

    it "disables Hashie key collision warnings" do
      assert_predicate AcmeApi::Result, :disable_warnings?
    end
  end
end
