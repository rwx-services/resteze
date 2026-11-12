require "test_helper"

module Resteze
  class BodyErrorTest < Minitest::Spec
    def stub_track(body, status: 201)
      stub_request(:post, "http://body.example.com/users/track")
        .to_return(status:, body: JSON.generate(body), headers: { "Content-Type" => "application/json" })
    end

    describe "Response.body_error" do
      it "defaults to accepting every response" do
        response = Resteze::Response.new
        response.data = { message: "anything", errors: ["ignored"] }

        assert_nil Resteze::Response.body_error(response)
      end

      it "accepts a successful body" do
        stub_track({ message: "success", events_processed: 3 })

        result = BodyApi::User.track(events: [{ name: "signup" }])

        assert_equal 3, result.events_processed
      end

      it "raises the returned error for a 2xx body that reports errors" do
        stub_track({ message: "success", errors: [{ type: "invalid", input_array: "events", index: 0 }] })

        error = assert_raises(BodyApi::ApiError) { BodyApi::User.track(events: [{ name: "" }]) }

        assert_equal "success",  error.message
        assert_equal 201,        error.http_status
        assert_equal "invalid",  error.json_body[:errors].first[:type]
        assert_kind_of Resteze::Response, error.response
        assert_kind_of BodyApi::Error, error
      end

      it "raises for a non-success message" do
        stub_track({ message: "Invalid API key" }, status: 200)

        error = assert_raises(BodyApi::ApiError) { BodyApi::User.track(events: []) }

        assert_equal "HTTP 200: Invalid API key", error.to_s
      end

      it "runs after the status-based middleware, which wins for a 4xx" do
        stub_track({ message: "Invalid API key" }, status: 401)

        assert_raises(BodyApi::AuthenticationError) { BodyApi::User.track(events: []) }
      end

      it "reports the status to instrumentation" do
        stub_track({ message: "success", errors: ["bad"] })
        events = []
        subscriber = ActiveSupport::Notifications.subscribe("request.body_api") do |*args|
          events << ActiveSupport::Notifications::Event.new(*args)
        end

        assert_raises(BodyApi::ApiError) { BodyApi::User.track(events: []) }

        assert_equal 201, events.first.payload[:status]
        refute_nil events.first.payload[:exception]
      ensure
        ActiveSupport::Notifications.unsubscribe(subscriber)
      end
    end
  end
end
