require "test_helper"

module Resteze
  class Authenticator
    class BasicTest < Minitest::Spec
      URL = "http://auth.example.com/widgets/1".freeze

      after do
        AuthApi.authenticator = nil
      end

      def request
        Request.new(http_method: :get, path: "/widgets/1", headers: {}, params: {}, query: {})
      end

      it "is registered as :basic and expects username and password by default" do
        assert_equal Basic, Strategy.lookup(:basic)
        assert_equal %i[username password], Basic.settings
        assert_equal %i[api_user api_secret], Basic.settings(username: :api_user, password: :api_secret)
      end

      it "declares the settings when chosen and sends them as HTTP Basic" do
        Class.new(AuthApi::Authenticator) { strategy :basic }
        AuthApi.username = "u"
        AuthApi.password = "p"
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: Basic.new)
        stub_request(:get, URL).with(basic_auth: %w[u p]).to_return(body: "{}")

        AuthApi::Client.new.execute_request(:get, "/widgets/1")

        assert_requested :get, URL, times: 1
      ensure
        AuthApi.username = AuthApi.password = nil
      end

      it "encodes username:password in base64 and allows an empty password" do
        req = request
        Basic.new(username: "user", password: "pass").apply(req, {})

        assert_equal "Basic dXNlcjpwYXNz", req.headers["Authorization"]

        req = request
        Basic.new(username: -> { "secret" }, password: "").apply(req, {})

        assert_equal "Basic #{['secret:'].pack('m0')}", req.headers["Authorization"]
      end

      it "names the missing setting" do
        Class.new(AuthApi::Authenticator) { strategy :basic }
        AuthApi.username = "u"
        AuthApi.password = nil
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: Basic.new)

        error = assert_raises(ArgumentError) { AuthApi.authenticator.apply(request) }

        assert_match(/AuthApi\.password is not set; the basic authentication strategy needs it/, error.message)
        assert_equal %i[username password], AuthApi.authenticator.settings
        assert_equal %i[password], AuthApi.authenticator.missing_settings
      ensure
        AuthApi.username = nil
      end

      it "says so when a bare strategy has no module to read from" do
        error = assert_raises(ArgumentError) { Basic.new.apply(request, {}) }

        assert_match(/the API module\.username is not set/, error.message)
      end

      it "rejects nil options" do
        assert_raises(ArgumentError) { Basic.new(username: nil) }
        assert_raises(ArgumentError) { Basic.new(password: nil) }
      end
    end
  end
end
