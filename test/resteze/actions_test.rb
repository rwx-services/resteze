require "test_helper"

module Resteze
  class ActionsTest < Minitest::Spec
    # rubocop:disable Style/ClassAndModuleChildren
    class AcmeApi::Thing < AcmeApi::ApiResource
      action :ping
    end

    class AcmeApi::Invalid < AcmeApi::ApiResource; end

    class AcmeApi::Doohickey < AcmeApi::ApiResource
      property :id

      action :activate, method: :post, on: :member
    end

    class AcmeApi::Hooked < AcmeApi::ApiResource
      action :ping, method: :post

      def self.action_params(name, params) = params.merge(source: name.to_s)
      def self.action_headers(_name, _params) = { "X-Action" => "yes" }
    end

    class AcmeApi::Clash < AcmeApi::ApiResource
      property :status
    end

    class AcmeApi::Sender < AcmeApi::ApiResource
      action :send, method: :post, as: :deliver
    end

    class AcmeApi::Resender < AcmeApi::Sender
      action :send, path: "send_now"
    end
    # rubocop:enable Style/ClassAndModuleChildren

    module LateApi
      include Resteze

      class Thing < ApiResource; end
    end

    describe ".actions" do
      it "exposes the four built-ins with REST defaults when nothing is declared" do
        actions = AcmeApi::Widget.actions

        assert_equal %i[create list retrieve update], actions.keys.sort
        assert_predicate actions, :frozen?
        assert_equal :get, actions[:retrieve].http_method
        assert_equal :path, actions[:retrieve].id
        assert_equal "/widgets/1", actions[:retrieve].path_for("1")
        assert_equal "/widgets", actions[:list].path_for
      end

      it "applies module defaults and module declarations" do
        actions = VerbApi::Campaign.actions

        assert_equal :param, actions[:retrieve].id
        assert_equal "/campaigns/details", actions[:retrieve].path_for("abc")
        assert_equal "/campaigns/list", actions[:list].path_for
        assert_equal :post, actions[:update].http_method
        assert_equal "/campaigns/update", actions[:update].path_for("abc")
      end

      it "lets a resource override the module" do
        assert_equal "/content_blocks/info", VerbApi::ContentBlock.actions[:retrieve].path_for("x")
      end

      it "lets a module declaration supply a custom action's method" do
        assert_equal :post, VerbApi::User.actions[:export].http_method
        refute VerbApi::Campaign.actions.key?(:export), "module-level custom actions are not visible unless declared"
      end

      it "inherits and overrides per option without touching the parent" do
        assert_equal :post, VerbApi::SpecialCampaign.actions[:duplicate].http_method
        assert_equal "/special_campaigns/clone", VerbApi::SpecialCampaign.actions[:duplicate].path_for("1")
        assert_equal "/campaigns/duplicate", VerbApi::Campaign.actions[:duplicate].path_for("1")
        assert_empty VerbApi::SpecialCampaign.declared_actions.except(:duplicate)
      end

      it "resolves lazily so later module declarations take effect" do
        assert_equal "/things/1", LateApi::Thing.actions[:retrieve].path_for("1")
        LateApi.action :retrieve, path: "show"
        LateApi.action_defaults id: :param

        assert_equal "/things/show", LateApi::Thing.actions[:retrieve].path_for("1")
      end

      it "raises on first use of a custom action with no method" do
        error = assert_raises(ArgumentError) { AcmeApi::Thing.actions[:ping].http_method }

        assert_match(/ping/, error.message)
        assert_match(/Thing/, error.message)
      end
    end

    describe ".action validation" do
      subject { AcmeApi::Invalid }

      it "rejects unknown options" do
        assert_raises(ArgumentError) { subject.action :ping, verb: :get }
      end

      it "rejects on: for reserved names" do
        assert_raises(ArgumentError) { subject.action :retrieve, on: :collection }
      end

      it "rejects id options on collection actions" do
        assert_raises(ArgumentError) { subject.action :ping, method: :get, id: :param }
        assert_raises(ArgumentError) { subject.action :ping, method: :get, id_param: :x }
      end

      it "rejects returns: :list without List" do
        assert_raises(ArgumentError) { subject.action :ping, method: :get, returns: :list }
      end

      it "rejects unknown on: and id: values" do
        assert_raises(ArgumentError) { subject.action :ping, method: :get, on: :memberr }
        assert_raises(ArgumentError) { subject.action :ping, method: :post, on: :member, id: :params }
      end

      it "stores nothing when validation fails" do
        assert_empty subject.declared_actions
      end
    end

    describe "generated collection actions" do
      it "posts params as a JSON body and returns a Result" do
        stub_request(:post, verb_url("/users/track")).to_return(body: { message: "success" }.to_json)
        result = VerbApi::User.track(events: [{ name: "x" }])

        assert_requested :post, verb_url("/users/track"), body: { events: [{ name: "x" }] }.to_json
        assert_kind_of VerbApi::Result, result
        assert_equal "success", result.message
      end

      it "sends GET params as a query string" do
        stub_request(:get, verb_url("/campaigns/data_series")).with(query: { length: "7" }).to_return(body: "{}")
        VerbApi::Campaign.data_series(length: 7)

        assert_requested :get, verb_url("/campaigns/data_series"), query: { length: "7" }
      end

      it "routes a slashed path" do
        stub_request(:post, verb_url("/users/export/ids")).to_return(body: "{}")
        VerbApi::User.export_ids(external_ids: ["1"])

        assert_requested :post, verb_url("/users/export/ids")
      end
    end

    describe "generated member actions" do
      it "merges the id param into the body for :param placement" do
        stub_request(:post, verb_url("/campaigns/duplicate")).to_return(body: "{}")
        VerbApi::Campaign.new("abc").duplicate(name: "copy")

        assert_requested :post, verb_url("/campaigns/duplicate"), body: { campaign_id: "abc", name: "copy" }.to_json
      end

      it "offers a class form that takes the id first" do
        stub_request(:post, verb_url("/campaigns/duplicate")).to_return(body: "{}")
        VerbApi::Campaign.duplicate("abc", name: "copy")

        assert_requested :post, verb_url("/campaigns/duplicate"), body: { campaign_id: "abc", name: "copy" }.to_json
      end

      it "lets a consumer param override the id param" do
        stub_request(:post, verb_url("/campaigns/duplicate")).to_return(body: "{}")
        VerbApi::Campaign.new("abc").duplicate(campaign_id: "zzz")

        assert_requested :post, verb_url("/campaigns/duplicate"), body: { campaign_id: "zzz" }.to_json
      end

      it "puts the id in the path for :path placement" do
        stub_request(:post, api_url("/doohickeys/1/activate")).to_return(body: "{}")
        AcmeApi::Doohickey.new("1").activate

        assert_requested :post, api_url("/doohickeys/1/activate"), body: "{}"
      end

      it "raises InvalidRequestError for a blank id" do
        assert_raises(VerbApi::InvalidRequestError) { VerbApi::Campaign.new.duplicate(name: "copy") }
        assert_raises(VerbApi::InvalidRequestError) { VerbApi::Campaign.duplicate("", name: "copy") }
      end
    end

    describe "hooks" do
      it "passes params through action_params and headers through action_headers" do
        stub_request(:post, api_url("/hookeds/ping")).to_return(body: "{}")
        AcmeApi::Hooked.ping(a: 1)

        assert_requested :post, api_url("/hookeds/ping"), body: { a: 1, source: "ping" }.to_json,
                                                          headers: { "X-Action" => "yes" }
      end

      it "defaults to pass-through and empty headers" do
        assert_equal({ a: 1 }, AcmeApi::Widget.action_params(:x, { a: 1 }))
        assert_empty AcmeApi::Widget.action_headers(:x, {})
      end
    end

    describe "method-name collisions" do
      subject { AcmeApi::Clash }

      it "rejects a collection action that collides with a class method" do
        error = assert_raises(ArgumentError) { subject.action :send, method: :post }

        assert_match(/send/, error.message)
        assert_match(/as:/, error.message)
      end

      it "rejects a member action that collides with a Hash method" do
        assert_raises(ArgumentError) { subject.action :delete, method: :post, on: :member }
      end

      it "rejects a member action that collides with a property accessor" do
        assert_raises(ArgumentError) { subject.action :status, method: :get, on: :member }
      end

      it "accepts as: to pick a different method name" do
        subject.action :send, method: :post, as: :deliver

        assert_respond_to subject, :deliver
      end

      it "never generates for reserved names" do
        subject.action :create, path: "create"

        refute_respond_to subject, :create
      end
    end

    describe "subclass redeclaration" do
      it "keeps the inherited member scope for both call forms" do
        stub_request(:post, verb_url("/special_campaigns/clone")).to_return(body: "{}")
        VerbApi::SpecialCampaign.duplicate("1", name: "x")
        VerbApi::SpecialCampaign.new("2").duplicate(name: "y")

        assert_requested :post, verb_url("/special_campaigns/clone"), body: { special_campaign_id: "1", name: "x" }
        assert_requested :post, verb_url("/special_campaigns/clone"), body: { special_campaign_id: "2", name: "y" }
      end

      it "keeps the inherited as: name and never shadows the colliding method" do
        assert_respond_to AcmeApi::Resender, :deliver
        assert_equal "AcmeApi::Resender", AcmeApi::Resender.send(:name)
        assert_equal :deliver, AcmeApi::Resender.actions[:send].generated_name
        assert_equal "/resenders/send_now", AcmeApi::Resender.actions[:send].path_for
      end
    end

    describe "returns:" do
      it "builds one resource from a hash with returns: :self" do
        stub_request(:get, verb_url("/campaigns/featured")).to_return(body: { id: "1", name: "Hot" }.to_json)
        campaign = VerbApi::Campaign.featured

        assert_kind_of VerbApi::Campaign, campaign
        assert_equal "Hot", campaign.name
      end

      it "builds an array of resources from an array with returns: :self" do
        stub_request(:get, verb_url("/campaigns/featured")).to_return(body: [{ id: "1" }, { id: "2" }].to_json)
        campaigns = VerbApi::Campaign.featured

        assert_equal %w[1 2], campaigns.map(&:id)
        assert_kind_of VerbApi::Campaign, campaigns.first
      end

      it "unwraps object_key for a hash and wraps items for an array" do
        stub_request(:get, "http://wrap.example.com/things/featured")
          .to_return({ body: { item: { id: "1" } }.to_json }, { body: [{ id: "2" }, { id: "3" }].to_json })

        assert_equal "1", WrapApi::Thing.featured.id
        assert_equal %w[2 3], WrapApi::Thing.featured.map(&:id)
      end

      it "returns a new instance from a member action and leaves the receiver alone" do
        stub_request(:post, verb_url("/campaigns/duplicate")).to_return(body: { id: "def", name: "copy" }.to_json)
        original = VerbApi::Campaign.new("abc", values: { name: "orig" })
        copy = original.duplicate(name: "copy")

        assert_equal "def", copy.id
        assert_equal "abc", original.id
        assert_equal "orig", original.name
        refute_same original, copy
      end

      it "builds a ListObject with returns: :list using the resource's list_key" do
        stub_request(:get, verb_url("/campaigns/search")).with(query: { q: "x" })
                                                         .to_return(body: { campaigns: [{}, {}], page: 0 }.to_json)
        list = VerbApi::Campaign.search(q: "x")

        assert_kind_of VerbApi::ListObject, list
        assert_equal 2, list.length
        assert_equal({ page: 0 }, list.metadata)
      end

      it "builds the named Object subclass" do
        stub_request(:post, verb_url("/users/track")).to_return(body: { message: "success", events_processed: 2 }.to_json)
        result = VerbApi::User.track_typed(events: [])

        assert_kind_of VerbApi::TrackResult, result
        assert_equal 2, result.events_processed
      end

      it "returns non-hash, non-array data unchanged for returns: :self" do
        stub_request(:get, verb_url("/campaigns/featured")).to_return(status: 204, body: "")

        assert_equal "", VerbApi::Campaign.featured
      end
    end
  end
end
