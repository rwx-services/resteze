module Resteze
  class Authenticator
    # HTTP Basic: an Authorization header carrying the base64 of
    # "username:password".
    #
    #   strategy :basic, username: -> { MyApi.username }, password: -> { MyApi.password }
    class Basic < Strategy
      def initialize(username:, password:)
        super()
        @username = Strategy.required!(:username, username)
        @password = Strategy.required!(:password, password)
      end

      def apply(request, _state)
        credentials = "#{resolve!(:username, @username)}:#{resolve!(:password, @password)}"
        request.headers["Authorization"] = "Basic #{[credentials].pack('m0')}"
      end
    end
  end
end
