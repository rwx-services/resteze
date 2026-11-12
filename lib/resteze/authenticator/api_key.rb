module Resteze
  class Authenticator
    # An API key sent in a header (default X-Api-Key) or, with `query:`, as
    # a query-string parameter on every request regardless of HTTP method.
    #
    #   strategy :api_key, header: "X-Api-Key", value: -> { MyApi.api_key }
    #   strategy :api_key, header: "Authorization", value: -> { "Token #{MyApi.api_key}" }
    #   strategy :api_key, query: "api_key", value: -> { MyApi.api_key }
    class ApiKey < Strategy
      attr_reader :header, :query

      def initialize(value:, header: nil, query: nil)
        super()
        raise ArgumentError, "api_key takes header: or query:, not both" if header && query

        @value  = Strategy.required!(:value, value)
        @query  = query
        @header = query ? nil : (header || "X-Api-Key")
      end

      def apply(request, _state)
        key = resolve!(:value, @value).to_s
        if query
          request.query[query] = key
        else
          request.headers[header] = key
        end
      end
    end
  end
end
