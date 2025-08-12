require "test_helper"

module Resteze
  class ListObjectTest < Minitest::Spec
    module AcmeApi
      class YoYoL < ::AcmeApi::ApiResource
        include Resteze::List

        property :id
      end
    end

    subject { ::AcmeApi::ListObject }

    it "should be an instance of ListObject" do
      assert_kind_of ::AcmeApi::ListObject, subject.new
    end

    it "should have :_list object_key" do
      assert_equal :_list, subject.object_key
    end

    describe "construct_from" do
      before do
        @list = subject.construct_from({ num_accts: 1, data: [{ id: 1 }] }, AcmeApi::YoYoL)
      end

      it "should build a list" do
        refute_empty @list
      end
    end

    describe "#to_ary" do
      before do
        @list = subject.construct_from({ num_accts: 1, data: [{ id: 1 }] }, ::AcmeApi::Widget)
      end

      it "should respond" do
        assert_respond_to @list, :to_ary
      end

      it "should return itself" do
        assert_equal @list.to_ary, @list
      end
    end

    describe "enumerable" do
      before do
        arr = [{ id: 1 }, { id: 2 }]
        @list = subject.construct_from({ meta: 1, data: arr }, AcmeApi::YoYoL)
      end

      it "should provide #count" do
        assert_equal 2, @list.count
      end

      it "should provide #size" do
        assert_equal 2, @list.size
      end

      it "should provide #length" do
        assert_equal 2, @list.length
      end

      it "should provide #each" do
        refute_empty @list.each.to_a
      end

      it "should provide #empty" do
        refute_predicate @list, :empty?
      end

      it "should provide #[]" do
        assert_operator @list, :[], 0
      end

      it "should provide #first" do
        assert @list.first
      end

      it "should provide #last" do
        assert @list.last
      end

      it "should provide #<<" do
        @list << { id: 3 }

        assert_equal 3, @list.last[:id]
      end
    end

    it "should implement #==" do
      data = { num_accts: 1, _list: [{ id: 1 }] }
      obj1 = subject.new.initialize_from(data)
      obj2 = subject.new.initialize_from(data)
      obj3 = subject.new.initialize_from(data.merge(_list: [{ difference: 3 }]))
      obj4 = subject.new.initialize_from(data.merge(difference: 4))

      assert_equal obj1, obj2
      refute_equal obj1, obj3
      refute_equal obj1, obj4
    end

    describe "#as_json" do
      it "should generate proper json" do
        list = subject.construct_from({ "num_accts" => 1, "data" => [{ "id" => 1 }] }, AcmeApi::YoYoL)

        assert_equal([{ "id" => 1 }], list.as_json)
      end
    end

    describe "#as_list_json" do
      it "should generate proper json" do
        attributes = { "num_accts" => 1, "data" => [{ "id" => 1 }] }
        list = subject.construct_from(attributes, AcmeApi::YoYoL)

        assert_equal(attributes, list.as_list_json("data"))
      end
    end
  end
end
