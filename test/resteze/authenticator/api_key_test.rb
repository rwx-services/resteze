require "test_helper"

module Resteze
  class Authenticator
    class ApiKeyTest < Minitest::Spec
      URL = "http://auth.example.com/widgets/1".freeze

      after do
        AuthApi.authenticator = nil
      end

      def request
        Request.new(http_method: :get, path: "/widgets/1", headers: {}, params: {}, query: {})
      end

      it "is registered as :api_key and expects api_key by default" do
        assert_equal ApiKey, Strategy.lookup(:api_key)
        assert_equal %i[api_key], ApiKey.settings
        assert_equal %i[partner_key], ApiKey.settings(value: :partner_key)
      end

      it "sends the module's api_key in X-Api-Key by default" do
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: ApiKey.new)
        stub_request(:get, URL).with(headers: { "X-Api-Key" => "secret-key" }).to_return(body: '{"id":1}')

        assert_equal 1, AuthApi::Widget.retrieve(1).id
      end

      it "sends it in another header, or from another setting, or from a callable" do
        req = request
        ApiKey.new(header: "X-Partner-Key", value: -> { "pk" }).apply(req, {})
        ApiKey.new(header: "Authorization", value: "Token literal").apply(req, {})

        assert_equal "pk",            req.headers["X-Partner-Key"]
        assert_equal "Token literal", req.headers["Authorization"]
      end

      it "declares another setting when told to read one, and reports it" do
        Class.new(AuthApi::Authenticator) { strategy :api_key, header: "X-Partner-Key", value: :partner_key }

        assert_respond_to AuthApi, :partner_key=
        assert_equal %i[partner_key], ApiKey.new(value: :partner_key).settings
      end

      it "puts a query key in the query string even for a POST with a body" do
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: ApiKey.new(query: "api_key"))
        stub_request(:post, "http://auth.example.com/widgets")
          .with(query: { "api_key" => "secret-key" }, body: { name: "x" })
          .to_return(body: '{"id":2,"name":"x"}')

        widget = AuthApi::Widget.new(values: { name: "x" })
        widget.save

        assert_equal 2, widget.id
      end

      it "rejects header: and query: together and a nil value" do
        assert_raises(ArgumentError) { ApiKey.new(header: "H", query: "q") }
        assert_raises(ArgumentError) { ApiKey.new(value: nil) }
      end

      it "names the missing setting" do
        AuthApi.api_key = nil
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: ApiKey.new)

        error = assert_raises(ArgumentError) { AuthApi::Widget.retrieve(1) }

        assert_match(/AuthApi\.api_key is not set; the api_key authentication strategy needs it/, error.message)
      ensure
        AuthApi.api_key = "secret-key"
      end
    end
  end
end
