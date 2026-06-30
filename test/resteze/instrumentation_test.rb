require "test_helper"

module Resteze
  class InstrumentationTest < Minitest::Spec
    subject { AcmeApi::Client.new }

    before do
      stub_request(:get, api_url("/widgets/1"))
        .to_return(body: JSON.generate({ id: "1", foo: "bar" }), status: 200,
                   headers: { "Request-Id" => "req_abc123" })
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

    describe "INSTRUMENTATION_KEY" do
      it "is derived from the api_module name" do
        assert_equal "acme_api", AcmeApi::INSTRUMENTATION_KEY
      end
    end

    describe "#execute_request instrumentation" do
      it "fires an event named after the api_module" do
        events = capture_events("request.acme_api") do
          subject.execute_request(:get, "/widgets/1")
        end

        assert_equal 1, events.size
      end

      it "populates the payload with request and response details" do
        events = capture_events("request.acme_api") do
          subject.execute_request(:get, "/widgets/1")
        end

        event = events.first

        assert_equal :get,         event.payload[:method]
        assert_equal "/widgets/1", event.payload[:path]
        assert_equal 200,          event.payload[:status]
        assert_equal "req_abc123", event.payload[:request_id]
        assert_equal "AcmeApi",    event.payload[:api_module]
      end

      it "records a non-zero duration" do
        events = capture_events("request.acme_api") do
          subject.execute_request(:get, "/widgets/1")
        end

        assert_operator events.first.duration, :>, 0
      end

      it "fires the event and captures the exception on error" do
        stub_request(:get, api_url("/widgets/missing")).to_return(status: 404)

        events = capture_events("request.acme_api") do
          assert_raises(AcmeApi::ResourceNotFound) do
            subject.execute_request(:get, "/widgets/missing")
          end
        end

        assert_equal 1, events.size
        refute_nil events.first.payload[:exception]
      end
    end
  end
end
