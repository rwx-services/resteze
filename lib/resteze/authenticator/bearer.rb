module Resteze
  class Authenticator
    # A token in the Authorization header, "Bearer <token>" by default.
    # Use `scheme:` for APIs that want another prefix, such as "Token".
    # A token obtained elsewhere (an OAuth flow the application ran, say)
    # fits here through a callable.
    #
    #   strategy :bearer, token: -> { MyApi.api_key }
    #   strategy :bearer, token: -> { TokenStore.current }, scheme: "Token"
    class Bearer < Strategy
      attr_reader :scheme

      def initialize(token:, scheme: "Bearer")
        super()
        @token  = Strategy.required!(:token, token)
        @scheme = scheme
      end

      def apply(request, _state)
        request.headers["Authorization"] = "#{scheme} #{resolve!(:token, @token)}"
      end
    end
  end
end
