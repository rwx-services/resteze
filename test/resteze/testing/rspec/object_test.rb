require "test_helper"
require "rspec/expectations"
require "resteze/testing/rspec/object"

module Resteze
  module Testing
    # The gem's own suite is Minitest, so the RSpec helpers are driven here
    # the way an RSpec example group would drive them: an object that has
    # RSpec's matchers, a `subject`, and the helper module.
    class RSpecObjectTest < ::Minitest::Spec
      # rubocop:disable-next Style/ClassAndModuleChildren
      class AcmeApi::Whatsit < AcmeApi::Object
        property :id
        property :name,   required: true
        property :count,  default: 0
        property :title,  from: :headline
        property :amount, transform_with: lambda(&:to_i)
      end

      class Example
        include ::RSpec::Matchers
        include Resteze::Testing::RSpec::Object

        attr_reader :subject

        def initialize(subject)
          @subject = subject
        end
      end

      NOT_MET = ::RSpec::Expectations::ExpectationNotMetError

      def example_for(subject)
        Example.new(subject)
      end

      describe "has_action" do
        let(:example) { example_for(VerbApi::Campaign) }

        it "passes for a declared action" do
          example.has_action :data_series, method: :get, on: :collection, path: "/campaigns/data_series"
          example.has_action :duplicate, method: :post, on: :member, id: :param, id_param: :campaign_id,
                                         path: "/campaigns/duplicate", returns: :self, as: :duplicate
          example.has_action :retrieve, path: "/campaigns/details"
        end

        it "reports a missing action" do
          error = assert_raises(NOT_MET) { example.has_action :nope }

          assert_match(/nope/, error.message)
        end

        it "reports a wrong option" do
          assert_raises(NOT_MET) { example.has_action :data_series, method: :post }
          assert_raises(NOT_MET) { example.has_action :duplicate, path: "/campaigns/ID/duplicate" }
        end

        it "fills a nested resource's path_template tokens with their upcased names" do
          nested = example_for(NestApi::Item)

          nested.has_action :archive, path: "/catalogs/CATALOG_NAME/items/ID/archive"
          nested.has_action :bulk_update, path: "/catalogs/CATALOG_NAME/items/bulk_update"
          nested.has_action :retrieve, path: "/catalogs/CATALOG_NAME/items/ID"
          assert_raises(NOT_MET) { nested.has_action :archive, path: "/items/ID/archive" }
        end
      end

      describe "has_property" do
        let(:example) { example_for(AcmeApi::Whatsit) }

        it "passes for a declared property" do
          example.has_property :id
          example.has_property :name, required: true
          example.has_property :id, required: false
          example.has_property :count, default: 0
          example.has_property :title, from: :headline
          example.has_property :amount, transformed: true
          example.has_property :id, transformed: false
        end

        it "reports a missing property" do
          error = assert_raises(NOT_MET) { example.has_property :nope }

          assert_match(/nope/, error.message)
        end

        it "reports a wrong option" do
          assert_raises(NOT_MET) { example.has_property :id, required: true }
          assert_raises(NOT_MET) { example.has_property :name, required: false }
          assert_raises(NOT_MET) { example.has_property :count, default: 1 }
          assert_raises(NOT_MET) { example.has_property :title, from: :subject }
          assert_raises(NOT_MET) { example.has_property :id, transformed: true }
        end
      end
    end
  end
end
