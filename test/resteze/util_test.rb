require "test_helper"

module Resteze
  class UtilTest < Minitest::Spec
    class Thingy < AcmeApi::Widget
      def self.object_key
        nil
      end
    end

    subject { Resteze::Util }

    describe "Util modules that include Resteze::Util" do
      subject { AcmeApi::Util }

      it "should respond to all the same class methods as Resteze::Util" do
        assert_respond_to subject, :convert_to_object
        assert_respond_to subject, :normalize_headers
        assert_respond_to subject, :normalize_id
        assert_respond_to subject, :objects_to_ids
      end
    end

    describe ".convert_to_object" do
      it "should #convert_to_object should pass through unknown types" do
        obj = subject.convert_to_object(7, {})

        assert_equal 7, obj
      end

      it "should #convert_to_object should turn hashes into Resteze Objects" do
        obj = subject.convert_to_object({ foo: "bar" }, AcmeApi::Object)

        assert_kind_of Resteze::Object, obj
        assert_instance_of AcmeApi::Object, obj
        assert_equal({ foo: "bar" }, obj.property_bag)
      end

      it "should #convert_to_object should marshal other classes" do
        obj = subject.convert_to_object({ id: "1", foo: "bar" }, AcmeApi::Widget)

        assert_instance_of AcmeApi::Widget, obj
        assert_equal "bar", obj.foo
      end

      it "should #convert_to_object should marshal arrays" do
        obj = subject.convert_to_object([1, 2, 3], Resteze::Object)

        assert_equal [1, 2, 3], obj
      end

      it "should handle no object_key" do
        obj = subject.convert_to_object({ id: "1" }, Thingy)

        assert_instance_of Thingy, obj
        assert_equal "1", obj.id
      end
    end

    describe ".normalize_headers" do
      it "should normalize the format of a header key" do
        assert_equal({ "Request-Id" => nil },
                     subject.normalize_headers("Request-Id" => nil))
        assert_equal({ "Request-Id" => nil },
                     subject.normalize_headers("request-id" => nil))
        assert_equal({ "Request-Id" => nil },
                     subject.normalize_headers("Request-ID" => nil))
        assert_equal({ "Request-Id" => nil },
                     subject.normalize_headers(request_id: nil))
        assert_equal({ "Accountid" => "12" },
                     subject.normalize_headers(accountId: "12"))
      end

      it "should tolerate bad formatting" do
        assert_equal({ "Request-Id" => nil },
                     subject.normalize_headers("-Request--Id-" => nil))
        assert_equal({ "Request-Id" => nil },
                     subject.normalize_headers(request__id: nil))
      end
    end

    describe ".normalize_id" do
      it "should return a [string, hash] representation of the id if just an id is passed" do
        assert_equal ["123", {}], subject.normalize_id(123)
      end

      it "should return nil if blank is passed in" do
        assert_equal [nil, {}], subject.normalize_id(nil)
        assert_equal [nil, {}], subject.normalize_id(" ")
      end

      it "should extract this id from a passed hash of params" do
        params = { a: 123, b: 234, c: 345, id: 456 }
        expected = ["456", { a: 123, b: 234, c: 345 }]

        assert_equal expected, subject.normalize_id(params)
      end
    end

    describe ".objects_to_ids" do
      it "should return id when ApiResource" do
        assert_equal "1", subject.objects_to_ids(AcmeApi::Gadget.new("1"))
      end

      it "should return Array of ids when Array" do
        assert_equal ["1"], subject.objects_to_ids([AcmeApi::Gadget.new("1")])
      end

      it "should return Hash of ids when Hash" do
        assert_equal ({ my: "1" }), subject.objects_to_ids(my: AcmeApi::Gadget.new("1"))
      end

      it "should return obj when none of above" do
        assert_equal "1", subject.objects_to_ids("1")
      end
    end
  end
end
