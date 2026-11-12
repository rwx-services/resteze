require "test_helper"

module Resteze
  class AuthenticatorTest < Minitest::Spec
    URL = "http://auth.example.com/widgets/1".freeze

    after do
      AuthApi.authenticator = nil
    end

    def request(http_method = :get, path = "/widgets/1")
      Resteze::Authenticator::Request.new(http_method:, path:, headers: {}, params: {}, query: {})
    end

    describe "the interface" do
      subject { Resteze::Authenticator.new }

      it "is a no-op by default" do
        req = request

        assert_same req, subject.apply(req)
        assert_empty req.headers
        assert_empty subject.connection_options
        refute subject.refresh?(Resteze::AuthenticationError.new("nope"), 1)
        assert_empty subject.strategies
      end

      it "gives every API module its own subclass, instantiated once and replaceable" do
        assert_operator AuthApi::Authenticator, :<, Resteze::Authenticator
        assert_kind_of AuthApi::Authenticator, AuthApi.authenticator
        assert_same AuthApi.authenticator, AuthApi.authenticator

        custom = Resteze::Authenticator.new
        AuthApi.authenticator = custom

        assert_same custom, AuthApi.authenticator
        assert_equal AuthApi, custom.api_module
      end
    end

    describe "the module-level macros" do
      it "configure the module's Authenticator and RateLimiter without opening them" do
        assert_equal [HeaderKey, HeaderKey], MacroApi::Authenticator.strategy.map(&:first)
        assert_equal 2, MacroApi.authenticator.strategies.size
        assert_kind_of Resteze::RateLimiter::TokenBucket, MacroApi.rate_limiter.strategy
        assert_in_delta 5.0, MacroApi.rate_limiter.strategy.capacity
      end

      it "apply through the client like the class form" do
        MacroApi.second_key = "s"
        req = MacroApi.authenticator.apply(request)

        assert_equal "k", req.headers["X-Api-Key"]
        assert_equal "s", req.headers["X-Second"]
      end

      it "refuse to run on Resteze itself or on a module that has not included it" do
        assert_raises(ArgumentError) { Resteze.authenticate_with(HeaderKey) }
        assert_raises(ArgumentError) do
          Module.new.extend(Resteze::ClassMethods).rate_limit_with(:token_bucket, capacity: 1, refill_rate: 1)
        end
      end
    end

    describe "the strategy macro" do
      it "configures one or several strategies, inherited by subclasses" do
        klass = Class.new(Resteze::Authenticator) do
          strategy HeaderKey, value: "k"
          strategy HeaderKey, header: "X-Other", value: "o"
        end

        assert_equal [HeaderKey, HeaderKey], klass.strategy.map(&:first)
        assert_equal klass.strategy, Class.new(klass).strategy
        assert_equal 2, klass.new.strategies.size

        req = Class.new(klass).new.apply(request)

        assert_equal "k", req.headers["X-Api-Key"]
        assert_equal "o", req.headers["X-Other"]
      end

      it "rejects unknown names and options without a name" do
        assert_raises(ArgumentError) { Class.new(Resteze::Authenticator) { strategy :unknown_scheme, value: "x" } }
        assert_raises(ArgumentError) { Class.new(Resteze::Authenticator) { strategy(header: "X") } }
      end

      it "keeps state across calls for a strategy that uses it" do
        counting = Class.new(Authenticator::Strategy) do
          def apply(request, state)
            state[:counting_calls] = state.fetch(:counting_calls, 0) + 1
            request.headers["X-Call"] = state[:counting_calls].to_s
          end
        end
        authenticator = Class.new(Resteze::Authenticator) { strategy counting }.new

        assert_equal "1", authenticator.apply(request).headers["X-Call"]
        assert_equal "2", authenticator.apply(request).headers["X-Call"]
        assert_equal 2, authenticator.state[:counting_calls]
      end
    end

    describe "credentials from module settings" do
      it "declares the expected settings on the module when the scheme is declared" do
        assert_respond_to AuthApi, :api_key
        assert_respond_to AuthApi, :api_key=
        assert_respond_to MacroApi, :second_key
        refute_respond_to AcmeApi, :second_key
        assert_equal %i[api_key], AuthApi::Authenticator.settings
        assert_equal %i[second_key], MacroApi::Authenticator.settings
      end

      it "reports a strategy's settings from its DEFAULTS and options" do
        assert_equal %i[api_key],     HeaderKey.settings
        assert_equal %i[partner_key], HeaderKey.settings(value: :partner_key)
        assert_empty HeaderKey.settings(value: -> { "k" })
        assert_empty Authenticator::Strategy.settings
      end

      it "reads the setting on every request, so a rotated credential takes effect" do
        AuthApi.api_key = "rotated"
        stub_request(:get, URL).to_return(body: "{}")

        AuthApi::Client.new.execute_request(:get, "/widgets/1")

        assert_requested(:get, URL, headers: { "X-Api-Key" => "rotated" })
      ensure
        AuthApi.api_key = "secret-key"
      end

      it "names the missing setting when it is not configured" do
        AuthApi.api_key = nil

        error = assert_raises(ArgumentError) { AuthApi::Widget.retrieve(1) }

        assert_match(/AuthApi\.api_key is not set; the header_key authentication strategy needs it/, error.message)
        assert_equal %i[api_key], AuthApi.authenticator.missing_settings
      ensure
        AuthApi.api_key = "secret-key"

        assert_empty AuthApi.authenticator.missing_settings
      end

      it "accepts a callable or a literal in place of a setting name" do
        req = AuthApi::Authenticator.new(strategies: [HeaderKey.new(value: -> { "called" }),
                                                      HeaderKey.new(header: "X-Lit", value: "literal")]).apply(request)

        assert_equal "called",  req.headers["X-Api-Key"]
        assert_equal "literal", req.headers["X-Lit"]

        error = assert_raises(ArgumentError) { HeaderKey.new(value: -> {}).apply(request, {}) }

        assert_match(/value: resolved to nil/, error.message)
      end

      it "reads settings from the module a replacement authenticator is assigned to" do
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: HeaderKey.new(header: "X-Replaced"))
        stub_request(:get, URL).to_return(body: "{}")

        AuthApi::Client.new.execute_request(:get, "/widgets/1")

        assert_requested(:get, URL, headers: { "X-Replaced" => "secret-key" })
      end
    end

    describe "the request lifecycle" do
      it "adds the module's credential to every request" do
        stub_request(:get, URL).with(headers: { "X-Api-Key" => "secret-key" }).to_return(body: '{"id":1}')

        assert_equal 1, AuthApi::Widget.retrieve(1).id
      end

      it "puts request.query in the query string even for a POST with a body" do
        query_key = Class.new(Authenticator::Strategy) do
          def apply(request, _state)
            request.query["api_key"] = "k"
          end
        end
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: query_key.new)
        stub_request(:post, "http://auth.example.com/widgets").with(query: { "api_key" => "k" }, body: { name: "x" })
                                                              .to_return(body: '{"id":2,"name":"x"}')

        widget = AuthApi::Widget.new(values: { name: "x" })
        widget.save

        assert_equal 2, widget.id
      end

      it "retries once with a renewed credential when a strategy says so" do
        renewing = Class.new(Authenticator::Strategy) do
          def apply(request, state)
            request.headers["Authorization"] = "Bearer #{state.fetch(:token, 'stale')}"
          end

          def refresh?(_error, attempt, state)
            return false if attempt > 1

            state[:token] = "fresh"
            true
          end
        end
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: renewing.new)
        stub_request(:get, URL).with(headers: { "Authorization" => "Bearer stale" }).to_return(status: 401)
        stub_request(:get, URL).with(headers: { "Authorization" => "Bearer fresh" }).to_return(body: '{"id":1}')

        assert_equal 1, AuthApi::Widget.retrieve(1).id
        assert_requested :get, URL, times: 2
      end

      it "gives up when the strategy will not renew" do
        stub_request(:get, URL).to_return(status: 401)

        assert_raises(AuthApi::AuthenticationError) { AuthApi::Widget.retrieve(1) }
        assert_requested :get, URL, times: 1
      end

      it "leaves a module without strategies untouched" do
        stub_request(:get, api_url("/widgets/1")).to_return(body: "{}")

        AcmeApi::Client.new.execute_request(:get, "/widgets/1")

        assert_requested(:get, api_url("/widgets/1")) do |req|
          !req.headers.key?("Authorization") && !req.headers.key?("X-Api-Key")
        end
      end
    end

    describe "connection options" do
      it "builds the Faraday connection with the strategies' options, merged" do
        verify_off = Class.new(Authenticator::Strategy) { def connection_options = { ssl: { verify: false } } }
        ca_file    = Class.new(Authenticator::Strategy) { def connection_options = { ssl: { ca_file: "/tmp/ca.pem" } } }
        AuthApi.authenticator = Resteze::Authenticator.new(strategies: [verify_off.new, ca_file.new])
        Thread.current["#{AuthApi::Client.client_name}_default_connection"] = nil

        ssl = AuthApi::Client.default_connection.ssl

        refute ssl.verify
        assert_equal "/tmp/ca.pem", ssl.ca_file
      ensure
        Thread.current["#{AuthApi::Client.client_name}_default_connection"] = nil
      end
    end
  end
end
