require "test_helper"

module Resteze
  class Authenticator
    class BearerTest < Minitest::Spec
      URL = "http://auth.example.com/widgets/1".freeze

      after do
        AuthApi.authenticator = nil
      end

      def request
        Request.new(http_method: :get, path: "/widgets/1", headers: {}, params: {}, query: {})
      end

      it "is registered as :bearer and expects api_key by default" do
        assert_equal Bearer, Strategy.lookup(:bearer)
        assert_equal %i[api_key], Bearer.settings
        assert_equal %i[access_token], Bearer.new(token: :access_token).settings
      end

      it "sends the module's api_key as a bearer token" do
        AuthApi.authenticator = Resteze::Authenticator.new(strategies: [Bearer.new])
        stub_request(:get, URL).with(headers: { "Authorization" => "Bearer secret-key" }).to_return(body: '{"id":1}')

        assert_equal 1, AuthApi::Widget.retrieve(1).id
      end

      it "takes another scheme prefix, another setting, a callable or a literal" do
        tokens = %w[first second]
        bearer = Bearer.new(token: -> { tokens.shift }, scheme: "Token")
        AuthApi.authenticator = Resteze::Authenticator.new(strategies: [bearer])
        stub_request(:get, URL).to_return(body: "{}")

        2.times { AuthApi::Client.new.execute_request(:get, "/widgets/1") }

        assert_requested(:get, URL, headers: { "Authorization" => "Token first" }, times: 1)
        assert_requested(:get, URL, headers: { "Authorization" => "Token second" }, times: 1)

        req = request
        Bearer.new(token: "literal").apply(req, {})

        assert_equal "Bearer literal", req.headers["Authorization"]
      end

      it "declares another setting when told to read one" do
        Class.new(AuthApi::Authenticator) { strategy :bearer, token: :access_token }

        assert_respond_to AuthApi, :access_token=
      end

      it "names the missing setting and rejects a nil token" do
        AuthApi.api_key = nil
        AuthApi.authenticator = Resteze::Authenticator.new(strategies: [Bearer.new])

        error = assert_raises(ArgumentError) { AuthApi::Widget.retrieve(1) }

        assert_match(/AuthApi\.api_key is not set; the bearer authentication strategy needs it/, error.message)
        assert_raises(ArgumentError) { Bearer.new(token: nil) }
      ensure
        AuthApi.api_key = "secret-key"
      end
    end
  end
end
