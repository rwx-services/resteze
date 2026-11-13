require "openssl"

module Resteze
  class Authenticator
    # Mutual TLS: the client presents a certificate when the connection is
    # made. The certificate and key are `MyApi.client_cert` and
    # `MyApi.client_key` unless told otherwise, each a PEM string or a path
    # to a PEM file; `MyApi.client_key_passphrase` decrypts an encrypted
    # key. `ca_file:` is a path to the CA bundle that verifies the server,
    # when the system store is not enough. Paths are read as given when the
    # connection is first built, so a relative one resolves against the
    # process's working directory at that moment; use absolute paths
    # (Rails.root.join, File.expand_path) or supply PEM text. Nothing is
    # added to requests; the credential lives in the connection, so a
    # client that overrides `default_connection` must pass
    # `connection_options` to Faraday itself.
    #
    #   authenticate_with :mtls                      # MyApi.client_cert and MyApi.client_key
    #   authenticate_with :mtls, cert: Rails.root.join("config/certs/client.pem"),
    #                            key:  Rails.root.join("config/certs/client-key.pem")
    class Mtls < Strategy
      DEFAULTS = { cert: :client_cert, key: :client_key, passphrase: :client_key_passphrase }.freeze

      def initialize(cert: :client_cert, key: :client_key, passphrase: :client_key_passphrase, ca_file: nil,
                     verify: true)
        super()
        @cert       = Strategy.required!(:cert, cert)
        @key        = Strategy.required!(:key, key)
        @ca_file    = ca_file
        @passphrase = passphrase
        @verify     = verify
      end

      def credential_options
        { cert: @cert, key: @key, passphrase: @passphrase }
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

      Strategy.register(:mtls, self)

      private

      def pem(value)
        value = value.to_s
        value.include?("-----BEGIN") ? value : File.read(value)
      end
    end
  end
end
