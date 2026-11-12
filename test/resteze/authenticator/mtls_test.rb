require "test_helper"
require "tmpdir"

module Resteze
  class Authenticator
    class MtlsTest < Minitest::Spec
      CONNECTION_KEY = "#{AuthApi::Client.client_name}_default_connection".freeze

      after do
        AuthApi.authenticator = nil
        Thread.current[CONNECTION_KEY] = nil
        %i[client_cert client_key client_key_passphrase].each do |setting|
          AuthApi.public_send(:"#{setting}=", nil) if AuthApi.respond_to?(:"#{setting}=")
        end
      end

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

      it "is registered as :mtls and expects client_cert, client_key and client_key_passphrase" do
        assert_equal Mtls, Strategy.lookup(:mtls)
        assert_equal %i[client_cert client_key client_key_passphrase], Mtls.settings
        assert_equal %i[client_key_passphrase], Mtls.new(cert: "a.pem", key: "b.pem").settings
      end

      it "builds the connection from PEM in the module's settings, alongside another scheme" do
        cert, key = self_signed
        Class.new(AuthApi::Authenticator) { strategy :mtls }
        AuthApi.client_cert = cert.to_pem
        AuthApi.client_key  = key.to_pem
        AuthApi.authenticator = Resteze::Authenticator.new(strategies: [Mtls.new(ca_file: "/tmp/ca.pem"), ApiKey.new])
        Thread.current[CONNECTION_KEY] = nil

        ssl = AuthApi::Client.default_connection.ssl

        assert_equal cert.to_pem, ssl.client_cert.to_pem
        assert_equal key.to_pem,  ssl.client_key.to_pem
        assert_equal "/tmp/ca.pem", ssl.ca_file
        assert ssl.verify
      end

      it "reads certificates from files and decrypts a passphrase-protected key" do
        cert, key = self_signed
        dir = Dir.mktmpdir
        File.write("#{dir}/client.pem", cert.to_pem)
        File.write("#{dir}/client-key.pem", key.export(OpenSSL::Cipher.new("aes-256-cbc"), "pw"))
        mtls = Mtls.new(cert: "#{dir}/client.pem", key: -> { Pathname.new("#{dir}/client-key.pem") }, passphrase: "pw",
                        verify: false)
        options = mtls.connection_options

        assert_equal cert.to_pem, options[:ssl][:client_cert].to_pem
        assert_equal key.to_pem,  options[:ssl][:client_key].to_pem
        refute options[:ssl][:verify]
        refute options[:ssl].key?(:ca_file)
      ensure
        FileUtils.rm_rf(dir)
      end

      it "adds nothing to requests" do
        cert, key = self_signed
        req = Request.new(http_method: :get, path: "/", headers: {}, params: {}, query: {})
        Mtls.new(cert: cert.to_pem, key: key.to_pem).apply(req, {})

        assert_empty req.headers
        assert_empty req.query
      end

      it "names the missing setting when the connection is built, and rejects nil options" do
        Class.new(AuthApi::Authenticator) { strategy :mtls }
        AuthApi.authenticator = Resteze::Authenticator.new(strategy: Mtls.new)
        Thread.current[CONNECTION_KEY] = nil

        error = assert_raises(ArgumentError) { AuthApi::Client.default_connection }

        assert_match(/AuthApi\.client_cert is not set; the mtls authentication strategy needs it/, error.message)
        assert_equal %i[client_cert client_key client_key_passphrase], AuthApi.authenticator.missing_settings
        assert_raises(ArgumentError) { Mtls.new(cert: nil, key: "k") }
      end
    end
  end
end
