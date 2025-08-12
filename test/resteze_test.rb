require "test_helper"

class RestezeTest < Minitest::Spec
  class Rusty
    include Resteze

    class << self
      def default_service_path(_klass)
        "/service"
      end

      def default_api_version(_klass)
        "/v1"
      end

      def default_resource_slug(klass)
        klass.name.demodulize.pluralize
      end

      def default_object_key(klass)
        klass.name.demodulize.camelcase(:lower)
      end

      def default_list_key(klass)
        default_object_key(klass).pluralize
      end

      def default_api_key(attribute)
        attribute.to_s.camelcase(:lower)
      end
    end

    class Nail < Rusty::ApiResource
      property :id
    end

    class Screw < Rusty::ApiResource
      include Save
      include List
    end
  end

  after { reset_gem! }
  subject { AcmeApi }

  it "should have a version number" do
    assert_match(/\d+\.\d+\.\d+/, Resteze::VERSION)
  end

  describe ".configure" do
    before do
      AcmeApi.configure do |config|
        config.api_base = "https://foobar"
        config.open_timeout = 120
        config.read_timeout = 360
      end
    end

    it "should pass configuration" do
      assert_equal "https://foobar", AcmeApi.api_base
      assert_equal 120, AcmeApi.open_timeout
      assert_equal 360, AcmeApi.read_timeout
    end
  end

  describe ".default_service_path" do
    it "should return the expected result" do
      assert_equal "/", AcmeApi.default_service_path(AcmeApi::Widget)
    end
  end

  describe ".default_api_version" do
    it "should return nil" do
      assert_nil AcmeApi.default_api_version(AcmeApi::Widget)
    end
  end

  describe ".default_resource_slug" do
    it "should return an underscored and pluralized value" do
      assert_equal "gadgets", AcmeApi.default_resource_slug(AcmeApi::Gadget)
      assert_equal "gizmo_devices", AcmeApi.default_resource_slug(AcmeApi::GizmoDevice)
    end
  end

  describe ".default_object_key" do
    it "should return nil" do
      assert_nil AcmeApi.default_object_key(AcmeApi::Widget)
    end
  end

  describe ".default_list_key" do
    it "should return :data" do
      assert_equal :data, AcmeApi.default_list_key(AcmeApi::Widget)
    end
  end

  describe ".default_api_key" do
    it "should return the passed in API key as a string" do
      assert_equal "description", AcmeApi.default_api_key("description")
      assert_equal "thing_id", AcmeApi.default_api_key(:thing_id)
    end
  end

  it "should support all built-in config properties" do
    assert_config_property(:logger)
    assert_config_property(:api_base)
    assert_config_property(:open_timeout, 30)
    assert_config_property(:read_timeout, 45)
    assert_config_property(:proxy)
  end

  it "should support custom config properties" do
    assert_config_property(:api_key)
  end

  it "should have default open and read timeout values" do
    assert_equal 30, subject.open_timeout
    assert_equal 60, subject.read_timeout
  end

  it "should have a default logger" do
    assert_instance_of Logger, subject.logger
  end

  it "should allow for a custom api_base" do
    assert_equal "http://acme.example.com/", subject.api_base
  end

  describe "given a newly defined Resteze API namespace" do
    subject { Rusty }

    describe ".default_service_path" do
      it "should return the override" do
        assert_equal "/service", Rusty.default_service_path(Rusty::Nail)
      end
    end

    describe ".default_api_version" do
      it "should return the override" do
        assert_equal "/v1", Rusty.default_api_version(Rusty::Nail)
      end
    end

    describe ".default_resource_slug" do
      it "should return the override" do
        assert_equal "Nails", Rusty.default_resource_slug(Rusty::Nail)
        assert_equal "Screws", Rusty.default_resource_slug(Rusty::Screw)
      end
    end

    describe ".default_object_id" do
      it "should return override" do
        assert_equal "nail", Rusty.default_object_key(Rusty::Nail)
        assert_equal "screw", Rusty.default_object_key(Rusty::Screw)
      end
    end

    describe ".default_list_key" do
      it "should return override" do
        assert_equal "nails", Rusty.default_list_key(Rusty::Nail)
        assert_equal "screws", Rusty.default_list_key(Rusty::Screw)
      end
    end

    describe ".default_api_key" do
      it "should return override" do
        assert_equal "description", Rusty.default_api_key("description")
        assert_equal "thingId", Rusty.default_api_key(:thing_id)
      end
    end

    it "should define modules/classes under the Rusty namespace" do
      expected_constants = %i[
        Client
        Object
        ApiResource
        List
        Save
        Util
        Response
        Error
        InvalidRequestError
        ApiConnectionError
        ApiError
        NotImplementedError
        ResourceNotFound
        UnprocessableEntityError
        ConflictError
      ]

      expected_constants.each do |constant|
        assert subject.const_defined?(constant), "#{subject}::#{constant} is missing"
      end
    end

    it "should ensure api resources inherit from Rusty::ApiResource and Rusty::Object" do
      nail = Rusty::Nail.new

      assert_kind_of Rusty::ApiResource,   nail
      assert_kind_of Resteze::ApiResource, nail
      assert_kind_of Rusty::Object,        nail
      assert_kind_of Resteze::Object,      nail
    end

    it "should ensure saveable and listable resources include Rusty::Save and Rusty::List" do
      assert_includes Rusty::Screw, Rusty::Save
      assert_includes Rusty::Screw, Rusty::List
      assert_includes Rusty::Screw, Resteze::Save
      assert_includes Rusty::Screw, Resteze::List
    end
  end

  it "should have a valid api_url test helper" do
    assert_equal "http://acme.example.com/path", api_url("path")
  end

  def assert_config_property(property, value = "value", subject: nil)
    subject ||= (defined?(@subject) && @subject) || subject()
    old = subject.send(property)
    subject.send(:"#{property}=", value)

    assert_equal value, subject.send(property), "config property #{property} value did not match assignment value"
  ensure
    subject.send(:"#{property}=", old)
  end
end
