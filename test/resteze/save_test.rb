require "test_helper"

module Resteze
  # rubocop:disable Style/ClassAndModuleChildren
  class AcmeApi::YoYoS < AcmeApi::ApiResource
    include ::AcmeApi::Save

    property :id

    def self.resource_slug
      "toys"
    end
  end

  class AcmeApi::YoYoS2 < AcmeApi::YoYoS
    def retrieve_headers
      { foo: "bar" }
    end
  end
  # rubocop:enable Style/ClassAndModuleChildren

  class SaveTest < Minitest::Spec
    subject { AcmeApi::YoYoS }

    describe "#save_method" do
      it "should return :post if not yet persisted" do
        assert_equal :post, subject.new.save_method
      end

      it "should return :put if already persisted" do
        assert_equal :put, subject.new(1).save_method
      end
    end

    describe "#save_resource_path" do
      it "should default to list path if not yet persisted" do
        assert_equal "/toys", subject.new.save_resource_path
      end

      it "should default to id path if already persisted" do
        assert_equal "/toys/3", subject.new(3).save_resource_path
      end
    end

    describe "#as_save_json" do
      it "should default to as_json" do
        yoyo = subject.new(1)

        assert_equal yoyo.as_json, subject.new(1).as_save_json
      end
    end

    describe ".save_headers" do
      it "should just return empty hash by default" do
        assert_equal ({}), subject.new.save_headers
      end

      it "should just return retrieve headers if defined" do
        assert_equal ({ foo: "bar" }), AcmeApi::YoYoS2.new.save_headers
      end
    end

    describe ".process_save_response" do
      it "should merge response values into object" do
        response = Struct.new(:data, keyword_init: true).new(data: { id: "12345" })
        yoyo = subject.new

        assert_nil yoyo.id
        yoyo.process_save_response(response)

        assert_equal "12345", yoyo.id
      end
    end

    describe "#save" do
      before do
        stub_request(:post, api_url("/toys")).to_return(body: { id: "4444" }.to_json)
        stub_request(:put, api_url("/toys/7")).to_return(body: {}.to_json)
      end

      it "should :post if not yet persisted" do
        subject.new.save

        assert_requested(:post, api_url("/toys"))
      end

      it "should merge values from response" do
        yoyo = subject.new
        yoyo.save

        assert_equal "4444", yoyo.id
      end

      it "should return :put if already persisted" do
        assert_equal :put, subject.new(1).save_method
      end
    end

    describe "routed save" do
      it "uses the create and update actions" do
        assert_equal :post, VerbApi::ContentBlock.new.save_method
        assert_equal :post, VerbApi::ContentBlock.new("x").save_method
        assert_equal "/content_blocks/create", VerbApi::ContentBlock.new.save_resource_path
        assert_equal "/content_blocks/update", VerbApi::ContentBlock.new("x").save_resource_path
      end

      it "merges the id param into save_params only when persisted with :param placement" do
        assert_equal "x", VerbApi::ContentBlock.new("x").save_params["content_block_id"]
        refute VerbApi::ContentBlock.new.save_params.key?("content_block_id")
        refute subject.new(1).save_params.key?("toy_id")
      end

      it "posts the update with the id in the body" do
        stub_request(:post, verb_url("/content_blocks/update")).to_return(body: { id: "x", content: "new" }.to_json)
        block = VerbApi::ContentBlock.new("x", values: { content: "new" })
        block.save

        assert_requested :post, verb_url("/content_blocks/update"),
                         body: { "content_block_id" => "x", "id" => "x", "content" => "new" }
        assert_equal "new", block.content
      end
    end
  end
end
