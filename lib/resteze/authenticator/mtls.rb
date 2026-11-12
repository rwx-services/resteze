require "openssl"

module Resteze
  class Authenticator
    # Mutual TLS: the client presents a certificate when the connection is
    # made. `cert:` and `key:` are PEM strings, paths to PEM files, or
    # callables returning either; `ca_file:` is a path to the CA bundle
    # that verifies the server, when the system store is not enough.
    # Nothing is added to requests; the credential lives in the
    # connection, so a client that overrides `default_connection` must
    # pass `connection_options` to Faraday itself.
    #
    #   strategy :mtls, cert: "config/client.pem", key: "config/client-key.pem"
    #   strategy :mtls, cert: -> { MyApi.client_cert }, key: -> { MyApi.client_key },
    #                   passphrase: -> { MyApi.client_key_passphrase }, ca_file: "config/ca.pem"
    class Mtls < Strategy
      def initialize(cert:, key:, ca_file: nil, passphrase: nil, verify: true)
        super()
        @cert       = Strategy.required!(:cert, cert)
        @key        = Strategy.required!(:key, key)
        @ca_file    = ca_file
        @passphrase = passphrase
        @verify     = verify
      end

      def connection_options
        { ssl: { client_cert: certificate, client_key: private_key, ca_file: resolve(@ca_file), verify: @verify }.compact }
      end

      def certificate
        OpenSSL::X509::Certificate.new(pem(resolve!(:cert, @cert)))
      end

      def private_key
        OpenSSL::PKey.read(pem(resolve!(:key, @key)), resolve(@passphrase))
      end

      private

      def pem(value)
        value = value.to_s
        value.include?("-----BEGIN") ? value : File.read(value)
      end
    end
  end
end
