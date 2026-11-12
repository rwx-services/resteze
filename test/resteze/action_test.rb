require "test_helper"

module Resteze
  class ActionTest < Minitest::Spec
    # rubocop:disable-next Style/ClassAndModuleChildren
    class AcmeApi::Keyed < AcmeApi::ApiResource
      def self.id_param
        :keyed_key
      end
    end

    def action(name, owner = AcmeApi::Widget, **options)
      Resteze::Action.new(name, owner, options)
    end

    describe "defaults" do
      it "defaults on to :collection and path to the name for custom actions" do
        a = action(:ping, method: :get)

        assert_equal :collection, a.on
        assert_equal "ping", a.path
        assert_predicate a, :collection?
        refute_predicate a, :reserved?
      end

      it "defaults path to nil for reserved names" do
        assert_nil action(:retrieve, **Action::BUILT_IN[:retrieve]).path
        assert_predicate action(:retrieve, **Action::BUILT_IN[:retrieve]), :reserved?
      end

      it "defaults id to :path for member actions and discards id options on collection actions" do
        assert_equal :path, action(:dup, method: :post, on: :member).id
        assert_nil action(:ping, method: :get, id: :param, id_param: :x).id
      end

      it "uses as for generated_name when given" do
        assert_equal :deliver, action(:send, method: :post, as: :deliver).generated_name
        assert_equal :ping, action(:ping, method: :get).generated_name
      end
    end

    describe "#http_method" do
      it "returns the method" do
        assert_equal :post, action(:ping, method: :post).http_method
      end

      it "raises when no method is set" do
        error = assert_raises(ArgumentError) { action(:ping).http_method }

        assert_match(/ping/, error.message)
        assert_match(/Widget/, error.message)
      end

      it "still reports the raw value through to_h" do
        assert_nil action(:ping).to_h[:method]
      end
    end

    describe "#id_param" do
      it "defaults to the singular slug plus _id" do
        assert_equal :widget_id, action(:dup, method: :post, on: :member).id_param
        assert_equal :gizmo_device_id, action(:dup, AcmeApi::GizmoDevice, method: :post, on: :member).id_param
      end

      it "prefers the option, then the owner's id_param" do
        assert_equal :wid, action(:dup, method: :post, on: :member, id_param: :wid).id_param
        assert_equal :keyed_key, action(:dup, AcmeApi::Keyed, method: :post, on: :member).id_param
      end
    end

    describe "#path_for" do
      it "builds the REST retrieve path" do
        assert_equal "/widgets/abc", action(:retrieve, **Action::BUILT_IN[:retrieve]).path_for("abc")
      end

      it "puts the segment after the id for :path member actions" do
        assert_equal "/widgets/abc/duplicate", action(:duplicate, method: :post, on: :member).path_for("abc")
      end

      it "omits the id for :param member actions" do
        a = action(:retrieve, method: :get, on: :member, path: "details", id: :param)

        assert_equal "/widgets/details", a.path_for("abc")
      end

      it "appends a collection segment" do
        assert_equal "/widgets/list", action(:list, method: :get, path: "list").path_for
        assert_equal "/widgets", action(:list, method: :get, path: nil).path_for
      end

      it "splits segments on / and escapes each part" do
        assert_equal "/widgets/export/ids", action(:export_ids, method: :post, path: "export/ids").path_for
        assert_equal "/widgets/a%7Cb", action(:odd, method: :get, path: "a|b").path_for
        assert_equal %w[export ids], action(:export_ids, method: :post, path: "export/ids").path_segments
      end

      it "honors a resource_path override" do
        assert_equal "/gizmos/list", action(:list, AcmeApi::GizmoDevice, method: :get, path: "list").path_for
      end
    end

    describe "destroy built-in" do
      it "pre-registers destroy as a reserved DELETE member action with no segment" do
        assert_includes Action::RESERVED, :destroy
        assert_equal({ method: :delete, on: :member, path: nil, id: :path }, Action::BUILT_IN[:destroy])

        destroy = action(:destroy, **Action::BUILT_IN[:destroy])

        assert_predicate destroy, :rest_default?
        assert_equal :delete, destroy.http_method
        assert_equal "/widgets/abc", destroy.path_for("abc")
      end
    end

    describe "#to_h" do
      it "includes every option plus name" do
        expected = { name: :dup, method: :post, on: :member, path: "dup", id: :param, id_param: :widget_id,
                     returns: :self, as: :dup }

        assert_equal expected, action(:dup, method: :post, on: :member, id: :param, returns: :self).to_h
      end
    end
  end
end
