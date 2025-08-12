require "test_helper"

module Resteze
  class ApiModuleTest < Minitest::Spec
    module AwesomeApi
      include Resteze

      class YoYo < AcmeApi::ApiResource
        class String < AcmeApi::Object
          class FingerLoop < AcmeApi::Object
          end
        end
      end
    end

    module A
      include Resteze

      class B < A::Object
        module C
          include Resteze

          class D < A::B::C::Object
          end
        end
      end
    end

    describe ".api_module" do
      it "should find the parent module that includes Resteze" do
        assert_equal AwesomeApi, AwesomeApi::YoYo.api_module
        assert_equal AwesomeApi, AwesomeApi::YoYo::String.api_module
        assert_equal AwesomeApi, AwesomeApi::YoYo::String::FingerLoop.api_module
      end

      it "should find the first parent module that includes Resteze" do
        assert_equal A,       A::B.api_module
        assert_equal A::B::C, A::B::C::D.api_module
      end

      it "should find the Resteze if found as a parent module" do
        assert_equal Resteze, Resteze::Object.api_module
      end
    end
  end
end
