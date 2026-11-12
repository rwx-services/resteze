require "test_helper"
require "resteze/testing/minitest"

module Resteze
  module Testing
    class MinitestConfigurationTest < ::Minitest::Spec
      include Resteze::Testing::Configuration

      subject { AcmeApi }

      it "passes when the config property holds the value" do
        assert_config_property :open_timeout, 30
      end

      it "accepts an explicit subject" do
        assert_config_property :read_timeout, 60, subject: AcmeApi
      end

      it "reports a mismatched value" do
        error = assert_raises(::Minitest::Assertion) { assert_config_property :open_timeout, 5 }

        assert_match(/open_timeout/, error.message)
      end

      it "leaves the config value in place" do
        assert_config_property :open_timeout, 30

        assert_equal 30, AcmeApi.open_timeout
      end
    end
  end
end
