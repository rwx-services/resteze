require "test_helper"

module Resteze
  # rubocop:disable Style/ClassAndModuleChildren
  class AcmeApi::Gizmo < AcmeApi::ApiResource
    include ::AcmeApi::Destroy

    property :id
    property :name
  end

  class AcmeApi::Gizmo2 < AcmeApi::Gizmo
    def retrieve_headers
      { foo: "bar" }
    end

    def process_destroy_response(_response)
      :gone
    end
  end

  class AcmeApi::OwnedGizmo < AcmeApi::Gizmo
    def resource_path
      "/owners/9/gizmos/#{id}"
    end
  end

  # Declaring the reserved name never generates a method; only the mixin does.
  class AcmeApi::Keepsake < AcmeApi::ApiResource
    property :id

    action :destroy, path: "remove"
  end
  # rubocop:enable Style/ClassAndModuleChildren

  class DestroyTest < Minitest::Spec
    subject { AcmeApi::Gizmo }

    it "is namespaced like List and Save" do
      assert_includes subject, AcmeApi::Destroy
      assert_includes subject, Resteze::Destroy
    end

    describe "#destroy_method" do
      it "is :delete by default" do
        assert_equal :delete, subject.new(1).destroy_method
      end
    end

    describe "#destroy_resource_path" do
      it "is the record's REST path" do
        assert_equal "/gizmos/3", subject.new(3).destroy_resource_path
      end

      it "honors an instance-level resource_path override" do
        assert_equal "/owners/9/gizmos/3", AcmeApi::OwnedGizmo.new(3).destroy_resource_path
      end

      it "raises on a blank id" do
        error = assert_raises(AcmeApi::InvalidRequestError) { subject.new.destroy_resource_path }

        assert_equal "id", error.param
      end
    end

    describe "#destroy_params" do
      it "is empty by default" do
        assert_empty subject.new(1).destroy_params
      end
    end

    describe "#destroy_headers" do
      it "is empty by default" do
        assert_empty subject.new(1).destroy_headers
      end

      it "uses retrieve_headers when defined" do
        assert_equal({ foo: "bar" }, AcmeApi::Gizmo2.new(1).destroy_headers)
      end
    end

    describe "#destroy" do
      it "sends DELETE to the record's path and returns an empty Result for 204" do
        stub_request(:delete, api_url("/gizmos/7")).to_return(status: 204, body: "")
        result = subject.new(7).destroy

        assert_requested :delete, api_url("/gizmos/7")
        assert_kind_of AcmeApi::Result, result
        assert_empty result
        assert_equal 204, result.http_response.http_status
      end

      it "exposes a JSON body through the Result" do
        stub_request(:delete, api_url("/gizmos/7")).to_return(body: { deleted: true }.to_json)

        assert result = subject.new(7).destroy
        assert result.deleted
      end

      it "raises on a blank id before any request" do
        assert_raises(AcmeApi::InvalidRequestError) { subject.new.destroy }
        assert_not_requested :delete, api_url("/gizmos/")
      end

      it "passes the response through process_destroy_response" do
        stub_request(:delete, api_url("/gizmo2s/7")).to_return(status: 204, body: "")

        assert_equal :gone, AcmeApi::Gizmo2.new(7).destroy
      end
    end

    describe ".destroy" do
      it "builds the record and destroys it" do
        stub_request(:delete, api_url("/gizmos/8")).to_return(status: 204, body: "")
        result = subject.destroy(8)

        assert_requested :delete, api_url("/gizmos/8")
        assert_kind_of AcmeApi::Result, result
      end
    end

    describe "routed destroy" do
      it "uses the module-level route and carries the id as a param" do
        stub_request(:post, verb_url("/campaigns/delete")).to_return(body: { message: "success" }.to_json)
        result = VerbApi::Campaign.destroy("abc")

        assert_requested :post, verb_url("/campaigns/delete"), body: { campaign_id: "abc" }
        assert_equal "success", result.message
        assert_equal :post, VerbApi::Campaign.new("abc").destroy_method
        assert_equal "/campaigns/delete", VerbApi::Campaign.new("abc").destroy_resource_path
        assert_equal({ campaign_id: "abc" }, VerbApi::Campaign.new("abc").destroy_params)
      end
    end

    describe "without the mixin" do
      it "declaring the reserved name generates no method" do
        refute_respond_to AcmeApi::Keepsake, :destroy
        refute AcmeApi::Keepsake.method_defined?(:destroy)
        assert_equal "/keepsakes/1/remove", AcmeApi::Keepsake.action_for(:destroy).path_for(1)
      end
    end
  end
end
