require "test_helper"
require "resteze/testing/minitest"

module Resteze
  module Testing
    class MinitestConfigurationTest < ::Minitest::Spec
      include Resteze::Testing::Configuration

      # A config object whose writer records assignments but never changes the value.
      class Stubborn
        attr_reader :mode, :writes

        def initialize
          @mode = :fixed
          @writes = []
        end

        def mode=(value)
          @writes << value
        end
      end

      subject { AcmeApi }

      it "assigns the value, asserts it round-trips, and restores the original" do
        assert_config_property :open_timeout, 5

        assert_equal 30, AcmeApi.open_timeout
      end

      it "accepts an explicit subject" do
        assert_config_property :read_timeout, 10, subject: AcmeApi

        assert_equal 60, AcmeApi.read_timeout
      end

      it "reports a value the writer does not keep and still restores the original" do
        stubborn = Stubborn.new
        error = assert_raises(::Minitest::Assertion) { assert_config_property :mode, :loose, subject: stubborn }

        assert_match(/mode/, error.message)
        assert_equal %i[loose fixed], stubborn.writes
      end
    end
  end
end
