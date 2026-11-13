require "openssl"

module Resteze
  class Authenticator
    # Mutual TLS: the client presents a certificate when the connection is
    # made. The certificate and key are `MyApi.client_cert` and
    # `MyApi.client_key` unless told otherwise, each a PEM string or a path
    # to a PEM file; `MyApi.client_key_passphrase` decrypts an encrypted
    # key and `MyApi.ca_file` names a CA bundle that verifies the server
    # when the system store is not enough. Both are optional. Paths are
    # read as given when the connection is first built, so a relative one
    # resolves against the process's working directory at that moment; use
    # absolute paths (Rails.root.join, File.expand_path) or supply PEM
    # text. Nothing is added to requests; the credential lives in the
    # connection, so a client that overrides `default_connection` must
    # pass `connection_options` to Faraday itself.
    #
    # `verify: false` turns server verification off, which defeats the
    # trust mutual TLS is for; it is logged every time the connection is
    # built so it does not survive from a development initializer unseen.
    #
    #   authenticate_with :mtls                      # MyApi.client_cert and MyApi.client_key
    #   authenticate_with :mtls, cert: Rails.root.join("config/certs/client.pem"),
    #                            key:  Rails.root.join("config/certs/client-key.pem")
    class Mtls < Strategy
      DEFAULTS = { cert: :client_cert, key: :client_key, passphrase: :client_key_passphrase, ca_file: :ca_file }.freeze
      OPTIONAL = %i[passphrase ca_file].freeze

      def initialize(cert: DEFAULTS[:cert], key: DEFAULTS[:key], passphrase: DEFAULTS[:passphrase],
                     ca_file: DEFAULTS[:ca_file], verify: true)
        super()
        @cert       = required!(:cert, cert)
        @key        = required!(:key, key)
        @passphrase = passphrase
        @ca_file    = ca_file
        @verify     = verify
      end

      def credential_options
        { cert: @cert, key: @key, passphrase: @passphrase, ca_file: @ca_file }
      end

      def connection_options
        warn_unverified unless @verify

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

      def warn_unverified
        logger = api_module.try(:logger) || Logger.new($stderr)
        logger.warn("#{api_module || 'This API'} uses mTLS with verify: false, so the server's certificate is not checked")
      end
    end
  end
end
