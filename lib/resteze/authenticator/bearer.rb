module Resteze
  class Authenticator
    # A token in the Authorization header, "Bearer <token>" by default,
    # read from `MyApi.api_key` unless `token:` names another setting. Use
    # `scheme:` for APIs that want another prefix, such as "Token". A token
    # the application obtained some other way fits here through a callable.
    #
    #   authenticate_with :bearer                                   # Bearer <MyApi.api_key>
    #   authenticate_with :bearer, token: :access_token, scheme: "Token"
    #   authenticate_with :bearer, token: -> { TokenStore.current }
    class Bearer < Strategy
      DEFAULTS = { token: :api_key }.freeze

      attr_reader :scheme

      def initialize(token: DEFAULTS[:token], scheme: "Bearer")
        super()
        @token  = required!(:token, token)
        @scheme = required!(:scheme, scheme)
      end

      def credential_options
        { token: @token }
      end

      def apply(request, _state)
        request.headers["Authorization"] = "#{scheme} #{resolve!(:token, @token)}"
      end

      Strategy.register(:bearer, self)
    end
  end
end
