require "test_helper"
require "resteze/testing/minitest"

module Resteze
  module Testing
    class MinitestObjectTest < ::Minitest::Spec
      # rubocop:disable-next Style/ClassAndModuleChildren
      class AcmeApi::Doodad < AcmeApi::Object
        property :id
        property :name,   required: true
        property :count,  default: 0
        property :title,  from: :headline
        property :amount, transform_with: lambda(&:to_i)
        property :at,     from: :when, with: lambda(&:to_s)
      end

      include Resteze::Testing::Minitest::Object

      describe "has_action" do
        subject { VerbApi::Campaign }

        it "passes for a declared action" do
          has_action :data_series, method: :get, on: :collection, path: "/campaigns/data_series"
          has_action :duplicate, method: :post, on: :member, id: :param, id_param: :campaign_id,
                                 path: "/campaigns/duplicate", returns: :self, as: :duplicate
          has_action :retrieve, path: "/campaigns/details"
        end

        it "reports a missing action" do
          error = assert_raises(::Minitest::Assertion) { has_action :nope }

          assert_match(/nope/, error.message)
        end

        it "reports a wrong option" do
          assert_raises(::Minitest::Assertion) { has_action :data_series, method: :post }
          assert_raises(::Minitest::Assertion) { has_action :duplicate, path: "/campaigns/ID/duplicate" }
        end
      end

      describe "has_property" do
        subject { AcmeApi::Doodad }

        it "passes for a declared property" do
          has_property :id
          has_property :name, required: true
          has_property :id, required: false
          has_property :count, default: 0
          has_property :title, from: :headline
          has_property :amount, transformed: true
          has_property :at, from: :when, transformed: true
          has_property :id, transformed: false
        end

        it "reports a missing property" do
          error = assert_raises(::Minitest::Assertion) { has_property :nope }

          assert_match(/nope/, error.message)
        end

        it "reports a wrong option" do
          assert_raises(::Minitest::Assertion) { has_property :id, required: true }
          assert_raises(::Minitest::Assertion) { has_property :name, required: false }
          assert_raises(::Minitest::Assertion) { has_property :count, default: 1 }
          assert_raises(::Minitest::Assertion) { has_property :title, from: :subject }
          assert_raises(::Minitest::Assertion) { has_property :id, transformed: true }
          assert_raises(::Minitest::Assertion) { has_property :amount, transformed: false }
        end
      end
    end
  end
end
