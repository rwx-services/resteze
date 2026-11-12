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

    describe "the strategy macro" do
      it "configures one or several strategies, inherited by subclasses" do
        klass = Class.new(Resteze::Authenticator) do
          strategy :api_key, value: "k"
          strategy :bearer, token: "t"
        end

        assert_equal [Authenticator::ApiKey, Authenticator::Bearer], klass.strategy.map(&:first)
        assert_equal klass.strategy, Class.new(klass).strategy
        assert_equal 2, klass.new.strategies.size

        req = Class.new(klass).new.apply(request)

        assert_equal "k",        req.headers["X-Api-Key"]
        assert_equal "Bearer t", req.headers["Authorization"]
      end

      it "rejects unknown names, options without a name, and missing credentials" do
        assert_raises(ArgumentError) { Class.new(Resteze::Authenticator) { strategy :oauth2, client_id: "x" } }
        assert_raises(ArgumentError) { Class.new(Resteze::Authenticator) { strategy(header: "X") } }
        assert_raises(ArgumentError) { Authenticator::ApiKey.new(value: nil) }
        assert_raises(ArgumentError) { Authenticator::ApiKey.new(value: "k", header: "H", query: "q") }
        assert_raises(ArgumentError) { Authenticator::Basic.new(username: "u", password: nil) }
        assert_raises(ArgumentError) { Authenticator::Bearer.new(token: nil) }
      end

      it "accepts a custom Strategy class" do
        custom = Class.new(Authenticator::Strategy) do
          def initialize(label:)
            super()
            @label = label
          end

          def apply(request, state)
            state[:custom_calls] = state.fetch(:custom_calls, 0) + 1
            request.headers["X-Label"] = "#{@label}-#{state[:custom_calls]}"
          end
        end
        authenticator = Class.new(Resteze::Authenticator) { strategy custom, label: "one" }.new

        assert_equal "one-1", authenticator.apply(request).headers["X-Label"]
        assert_equal "one-2", authenticator.apply(request).headers["X-Label"]
        assert_equal 2, authenticator.state[:custom_calls]
      end
    end

    describe "credentials from module settings" do
      it "reads the setting on every request, so a rotated credential takes effect" do
        AuthApi.api_key = "rotated"
        stub_request(:get, URL).to_return(body: "{}")

        AuthApi::Client.new.execute_request(:get, "/widgets/1")

        assert_requested(:get, URL, headers: { "X-Api-Key" => "rotated" })
      ensure
        AuthApi.api_key = "secret-key"
      end

      it "fails clearly when the setting is not configured" do
        AuthApi.api_key = nil

        error = assert_raises(ArgumentError) { AuthApi::Widget.retrieve(1) }

        assert_match(/value: for the api_key authentication strategy resolved to nil/, error.message)
      ensure
        AuthApi.api_key = "secret-key"
      end

      it "accepts a literal as well as a callable" do
        req = request
        Authenticator::Bearer.new(token: "literal").apply(req, {})

        assert_equal "Bearer literal", req.headers["Authorization"]
      end
    end

    describe "the request lifecycle" do
      it "adds the module's credential to every request" do
        stub_request(:get, URL).with(headers: { "X-Api-Key" => "secret-key" }).to_return(body: '{"id":1}')

        assert_equal 1, AuthApi::Widget.retrieve(1).id
      end

      it "sends HTTP Basic credentials" do
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: Authenticator::Basic.new(username: "u", password: "p"))
        stub_request(:get, URL).with(basic_auth: %w[u p]).to_return(body: "{}")

        AuthApi::Client.new.execute_request(:get, "/widgets/1")

        assert_requested :get, URL, times: 1
      end

      it "sends a bearer token, resolving a callable each time" do
        tokens = %w[first second]
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: Authenticator::Bearer.new(token: -> { tokens.shift }))
        stub_request(:get, URL).to_return(body: "{}")

        2.times { AuthApi::Client.new.execute_request(:get, "/widgets/1") }

        assert_requested(:get, URL, headers: { "Authorization" => "Bearer first" }, times: 1)
        assert_requested(:get, URL, headers: { "Authorization" => "Bearer second" }, times: 1)
      end

      it "puts a query API key in the query string even for a POST with a body" do
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: Authenticator::ApiKey.new(query: "api_key", value: "k"))
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

      it "gives up when the strategy will not renew again" do
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: Authenticator::Bearer.new(token: "t"))
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
      def self_signed
        key = OpenSSL::PKey::RSA.new(2048)
        [certificate_for(key), key]
      end

      def certificate_for(key)
        OpenSSL::X509::Certificate.new.tap do |cert|
          cert.version    = 2
          cert.serial     = 1
          cert.subject    = OpenSSL::X509::Name.parse("/CN=client")
          cert.issuer     = cert.subject
          cert.public_key = key.public_key
          cert.not_before = Time.now
          cert.not_after  = Time.now + 3600
          cert.sign(key, OpenSSL::Digest.new("SHA256"))
        end
      end

      it "builds the Faraday connection with the strategies' options" do
        cert, key = self_signed
        AuthApi.authenticator = Resteze::Authenticator.new(
          strategies: [Authenticator::Mtls.new(cert: cert.to_pem, key: -> { key.to_pem }, ca_file: "/tmp/ca.pem"),
                       Authenticator::ApiKey.new(value: "k")]
        )
        Thread.current["#{AuthApi::Client.client_name}_default_connection"] = nil

        ssl = AuthApi::Client.default_connection.ssl

        assert_equal cert.to_pem, ssl.client_cert.to_pem
        assert_equal key.to_pem,  ssl.client_key.to_pem
        assert_equal "/tmp/ca.pem", ssl.ca_file
        assert ssl.verify
      ensure
        Thread.current["#{AuthApi::Client.client_name}_default_connection"] = nil
      end

      it "reads certificates from files and decrypts a passphrase-protected key" do
        cert, key = self_signed
        dir = Dir.mktmpdir
        File.write("#{dir}/client.pem", cert.to_pem)
        File.write("#{dir}/client-key.pem", key.export(OpenSSL::Cipher.new("aes-256-cbc"), "pw"))
        mtls = Authenticator::Mtls.new(cert: "#{dir}/client.pem", key: "#{dir}/client-key.pem", passphrase: "pw",
                                       verify: false)
        options = mtls.connection_options

        assert_equal cert.to_pem, options[:ssl][:client_cert].to_pem
        assert_equal key.to_pem,  options[:ssl][:client_key].to_pem
        refute options[:ssl][:verify]
        refute options[:ssl].key?(:ca_file)
      ensure
        FileUtils.rm_rf(dir)
      end
    end
  end
end
