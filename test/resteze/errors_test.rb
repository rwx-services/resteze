require "test_helper"

module Resteze
  class ErrorsTest < Minitest::Spec
    def self.must_support_to_s(message = "message", *)
      describe "#to_s" do
        it "should convert to string" do
          e = subject.new(message, *)

          assert_equal message, e.to_s

          e = subject.new(message, *, http_status: 200)

          assert_equal "HTTP 200: #{message}", e.to_s
        end
      end
    end

    describe "Resteze::Error" do
      subject { Resteze::Error }
      must_support_to_s
    end

    describe "Resteze::InvalidRequestError" do
      subject { Resteze::InvalidRequestError }
      must_support_to_s("message", "id")
    end

    describe "Resteze::AuthenticationError" do
      subject { Resteze::AuthenticationError }
      must_support_to_s
    end

    describe "Resteze::ApiConnectionError" do
      subject { Resteze::ApiConnectionError }
      must_support_to_s
    end

    describe "Resteze::ApiError" do
      subject { Resteze::ApiError }
      must_support_to_s
    end

    describe "AcmeApi::Error" do
      subject { AcmeApi::Error }
      must_support_to_s
    end

    describe "AcmeApi::InvalidRequestError" do
      subject { AcmeApi::InvalidRequestError }
      must_support_to_s("message", "id")
    end

    describe "AcmeApi::AuthenticationError" do
      subject { AcmeApi::AuthenticationError }
      must_support_to_s
    end

    describe "AcmeApi::ApiConnectionError" do
      subject { AcmeApi::ApiConnectionError }
      must_support_to_s
    end

    describe "AcmeApi::ApiError" do
      subject { AcmeApi::ApiError }
      must_support_to_s
    end
  end
end
