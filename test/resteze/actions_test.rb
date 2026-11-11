require "test_helper"

module Resteze
  class ActionsTest < Minitest::Spec
    # rubocop:disable Style/ClassAndModuleChildren
    class AcmeApi::Thing < AcmeApi::ApiResource
      action :ping
    end

    class AcmeApi::Invalid < AcmeApi::ApiResource; end
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

      it "stores nothing when validation fails" do
        assert_empty subject.declared_actions
      end
    end
  end
end
