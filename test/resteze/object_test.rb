require "test_helper"

module Resteze
  class ObjectTest < Minitest::Spec
    class PersistableObject < Resteze::Object
      property :id
    end

    class TestObject < Resteze::Object
      property :id
      property :name
    end

    module AcmeApi
      class Cup < Resteze::Object
        property :color
        property :red
      end

      class Car < Resteze::Object
        property :id, from: :external_id
        property :color
        property :make

        def self.object_key
          :car
        end
      end
    end

    class WithObjectKey < TestObject
      def self.object_key
        :object
      end
    end

    class NoObjectKey < TestObject
    end

    subject { TestObject }

    it "should assign unknown keys to the property_bag" do
      obj = WithObjectKey.construct_from({ num_accts: 1, object: { id: 1, name: "foobar", city: "Detroit Lakes" } })

      assert_equal "Detroit Lakes", obj.property_bag[:city]
    end

    it "should assign any nodes outside the object_key to metadata" do
      obj = WithObjectKey.construct_from({ num_accts: 1, object: { id: 1, name: "foobar", city: "Detroit Lakes" } })

      assert_equal 1, obj.resteze_metadata[:num_accts]
    end

    it "should implement object_class" do
      assert_equal "TestObject", subject.class_name
    end

    it "should implement object_key" do
      assert_nil subject.object_key
    end

    it "should implement #==" do
      data = { num_accts: 1, object: { id: 1 } }
      obj1 = WithObjectKey.construct_from(data)
      obj2 = WithObjectKey.construct_from(data)
      obj3 = WithObjectKey.construct_from(data.merge(object: { difference: 3 }))

      assert_equal obj1, obj2
      refute_equal obj1, obj3
    end

    it "should be insensitive to strings vs symbols when constructing" do
      obj = subject.construct_from("id" => 1, "name" => "test")

      assert_equal 1, obj[:id]
      assert_equal "test", obj[:name]
    end

    describe "initialize" do
      subject do
        AcmeApi::Cup.new(
          color: "red",
          red: true
        )
      end

      it "should support initialize with params" do
        assert_equal "red", subject.color
        assert subject.red
      end
    end

    describe "#initialize_from" do
      it "should support with an object_key" do
        object_key = WithObjectKey.new.initialize_from(object: { id: 1, name: "test" })

        assert_equal 1, object_key[:id]
        assert_equal "test", object_key[:name]
      end

      it "should support with nil object_key" do
        no_object_key = NoObjectKey.new.initialize_from(id: 1, name: "test")

        assert_equal 1, no_object_key[:id]
        assert_equal "test", no_object_key[:name]
      end
    end

    describe "#merge_from" do
      before do
        @external_id = SecureRandom.uuid
        @car = AcmeApi::Car.construct_from(
          car: {
            id: 123,
            external_id: @external_id,
            color: "red"
          }
        )

        @merge_values = {
          car: {
            id: 123,
            external_id: @external_id,
            make: "Chevy"
          }
        }
      end

      subject { @car.merge_from(@merge_values) }

      it "should deep merge data and protect hashie translations" do
        assert_equal "Chevy", subject.make
        assert_equal @external_id, subject.id
      end

      it "should support with nil object_key" do
        no_object_key = NoObjectKey.new.merge_from(id: 1, name: "test")

        assert_equal 1, no_object_key[:id]
        assert_equal "test", no_object_key[:name]
      end
    end

    describe "#persisted?" do
      it "should not be persisted when no id" do
        refute_predicate Object.new, :persisted?
      end

      it "should not be persisted when no id" do
        obj = PersistableObject.new.tap { |p| p.id = 1 }

        assert_predicate obj, :persisted?
      end
    end

    describe "object methods" do
      subject { TestObject.new.initialize_from(id: 1, name: "test") }

      it "should implement []" do
        assert_equal 1, subject[:id]
      end

      it "should implement .keys" do
        assert_equal %i[id name], subject.keys
      end

      it "should implement .values" do
        assert_equal [1, "test"], subject.values
      end

      it "should implement .as_json" do
        expected = { "id" => 1, "name" => "test" }

        assert_equal expected, subject.as_json
      end

      it "should implement .to_hash" do
        assert_equal({ id: 1, name: "test" }, subject.to_hash)
      end
    end
  end
end
