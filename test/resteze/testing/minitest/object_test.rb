require "test_helper"
require "resteze/testing/minitest"

module Resteze
  module Testing
    class MinitestObjectTest < ::Minitest::Spec
      include Resteze::Testing::Minitest::Object

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
  end
end
