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

      def initialize(username: DEFAULTS[:username], password: DEFAULTS[:password])
        super()
        @username = required!(:username, username)
        @password = required!(:password, password)
      end

      def credential_options
        { username: @username, password: @password }
      end

      # A username cannot contain a colon (RFC 7617): the server splits on
      # the first one, so "acme:ops" would log in as "acme" and fail with a
      # bare 401. Better to say so here.
      def apply(request, _state)
        username = resolve!(:username, @username).to_s
        raise ArgumentError, "the basic authentication username #{username.inspect} contains ':'" if username.include?(":")

        credentials = "#{username}:#{resolve!(:password, @password)}"
        request.headers["Authorization"] = "Basic #{[credentials].pack('m0')}"
      end

      Strategy.register(:basic, self)
    end
  end
end
