module Resteze
  class Authenticator
    # An API key sent in a header (default X-Api-Key) or, with `query:`, as
    # a query-string parameter on every request regardless of HTTP method.
    # The key is `MyApi.api_key` unless `value:` names another setting.
    #
    #   authenticate_with :api_key                           # X-Api-Key: <MyApi.api_key>
    #   authenticate_with :api_key, header: "X-Partner-Key", value: :partner_key
    #   authenticate_with :api_key, query: "api_key"
    #   authenticate_with :api_key, header: "Authorization", value: -> { "Token #{MyApi.api_key}" }
    class ApiKey < Strategy
      DEFAULTS = { value: :api_key }.freeze

      attr_reader :header, :query

      def initialize(value: DEFAULTS[:value], header: nil, query: nil)
        super()
        raise ArgumentError, "api_key takes header: or query:, not both" if header && query

        @value  = required!(:value, value)
        @query  = query
        @header = query ? nil : (header || "X-Api-Key")
      end

      def credential_options
        { value: @value }
      end

      def apply(request, _state)
        key = resolve!(:value, @value).to_s
        if query
          request.query[query] = key
        else
          request.headers[header] = key
        end
      end

      Strategy.register(:api_key, self)
    end
  end
end
