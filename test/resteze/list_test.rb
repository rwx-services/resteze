require "test_helper"

module Resteze
  class ListTest < Minitest::Spec
    subject { AcmeApi::GizmoDevice }

    describe ".list" do
      before do
        stub_request(:get, api_url("/gizmos"))
          .to_return(body: { data: [{}, {}] }.to_json)
      end

      it "should build a list from a payload" do
        gizmos = subject.list

        assert_equal 2, gizmos.length
      end
    end

    describe ".construct_list_from" do
      it "should build a list from a payload" do
        payload = { data: [{}, {}] }
        gizmos = subject.construct_list_from(payload)

        assert_equal 2, gizmos.length
      end
    end

    describe ".construct_empty_list" do
      it "should build an empty list" do
        gizmos = subject.construct_empty_list

        assert_equal 0, gizmos.length
      end
    end

    describe ".list_params" do
      it "should just pass-thru values by default" do
        assert_equal ({ foo: :bar }), subject.list_params(foo: :bar)
      end
    end

    describe ".list_headers" do
      it "should just return empty hash by default" do
        assert_equal ({}), subject.list_headers(foo: :bar)
      end
    end

    describe ".list_resource_path" do
      it "should use resource_path by default" do
        assert_equal "/gizmos", subject.list_resource_path
      end
    end

    describe ".list_key" do
      it "should return :data by default" do
        assert_equal :data, subject.list_key
      end
    end

    describe ".list_method" do
      it "should default to :get" do
        assert_equal :get, subject.list_method
      end
    end
  end
end
