module Resteze
  class Authenticator
    # HTTP Basic: an Authorization header carrying the base64 of
    # "username:password", read from `MyApi.username` and `MyApi.password`
    # unless told otherwise.
    #
    #   authenticate_with :basic
    #   authenticate_with :basic, username: :api_user, password: :api_secret
    class Basic < Strategy
      DEFAULTS = { username: :username, password: :password }.freeze

      def initialize(username: :username, password: :password)
        super()
        @username = Strategy.required!(:username, username)
        @password = Strategy.required!(:password, password)
      end

      def credential_options
        { username: @username, password: @password }
      end

      def apply(request, _state)
        credentials = "#{resolve!(:username, @username)}:#{resolve!(:password, @password)}"
        request.headers["Authorization"] = "Basic #{[credentials].pack('m0')}"
      end

      Strategy.register(:basic, self)
    end
  end
end
