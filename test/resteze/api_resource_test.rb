require "test_helper"

module Resteze
  class ApiResourceTest < Minitest::Spec
    module AcmeApi
      class YoYoA < ::AcmeApi::ApiResource
        property :id
        property :color

        def self.api_version
          "v3"
        end

        def self.service_path
          "/toy-service"
        end

        def self.resource_slug
          "yo_yos"
        end
      end
    end

    subject { ::AcmeApi::ApiResource }

    describe ".service_path" do
      it "should have a default service_path" do
        assert_equal "/", subject.service_path
      end

      it "should allow for an override" do
        assert_equal "/toy-service", AcmeApi::YoYoA.service_path
      end
    end

    describe ".api_version" do
      it "should default to no api_version" do
        assert_nil subject.api_version
      end

      it "should allow for an override" do
        assert_equal "v3", AcmeApi::YoYoA.api_version
      end
    end

    describe ".api_path" do
      it "should build default paths" do
        assert_equal "/foo",       subject.api_path("foo")
        assert_equal "/bar",       subject.api_path("/bar")
        assert_equal "/fizz/buzz", subject.api_path("//fizz///buzz")
      end

      it "should build paths based on overrides" do
        assert_equal "/toy-service/v3/toys", AcmeApi::YoYoA.api_path("toys")
      end
    end

    describe ".resource_slug" do
      it "should return plural underscore version of the class" do
        assert_equal "widgets",       ::AcmeApi::Widget.resource_slug
        assert_equal "gizmo_devices", ::AcmeApi::GizmoDevice.resource_slug
      end

      it "should allow for an override" do
        assert_equal "yo_yos", AcmeApi::YoYoA.resource_slug
      end
    end

    describe ".resource_path" do
      it "should return base resource path" do
        assert_equal "/widgets", ::AcmeApi::Widget.resource_path
      end

      it "should return resource path with an optional id" do
        assert_equal "/toy-service/v3/yo_yos/123", AcmeApi::YoYoA.resource_path(123)
        assert_equal "/toy-service/v3/yo_yos/a%7Cb", AcmeApi::YoYoA.resource_path("a|b")
      end
    end

    describe "#initialize" do
      subject { AcmeApi::YoYoA }

      it "should accept an id as the first arg" do
        object = subject.new("123")

        assert_equal "123", object.id
        assert_empty object.retrieve_params
      end

      it "should accept an object hash of symbols as the first arg" do
        object = subject.new({ id: "234", key: "foo" })

        assert_equal "234", object.id
        assert_equal({ key: "foo" }, object.retrieve_params)
      end

      it "should accept an id and an object hash of values" do
        object = subject.new("234", values: { color: "red" })

        assert_equal "234", object.id
        assert_equal "red", object.color
      end
    end

    describe "#resource_path" do
      it "should not accept nil id" do
        assert_raises ::AcmeApi::InvalidRequestError do
          ::AcmeApi::Widget.new.resource_path
        end
      end

      it "should not accept blank id" do
        assert_raises ::AcmeApi::InvalidRequestError do
          ::AcmeApi::Widget.new("").resource_path
        end
      end

      it "should return path given an id" do
        assert_equal "/widgets/1", ::AcmeApi::Widget.new("1").resource_path
        assert_equal "/toy-service/v3/yo_yos/1", AcmeApi::YoYoA.new("1").resource_path
      end
    end

    describe "#retrieve" do
      before do
        stub_request(:get, api_url("/widgets/1")).to_return(body: JSON.generate(yoyo: {}))
      end

      it "should be refreshable" do
        widget = ::AcmeApi::Widget.new("1")
        widget.refresh

        assert_requested :get, api_url("/widgets/1")
      end

      it "should be an AcmeApi::Widget" do
        widget = ::AcmeApi::Widget.retrieve("1")

        assert_kind_of ::AcmeApi::Widget, widget
      end
    end

    describe "#retrieve_method" do
      it "should return the default method" do
        assert_equal :get, AcmeApi::YoYoA.new(1).retrieve_method
      end
    end

    describe "#retrieve_headers" do
      it "should return default retrieve_headers" do
        assert_empty AcmeApi::YoYoA.new("1").retrieve_headers
      end
    end
  end
end
