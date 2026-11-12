module Resteze
  class Error < StandardError
    include Resteze::ApiModule

    attr_accessor :response
    attr_reader   :message, :code, :http_body, :http_headers, :http_status, :json_body

    # Faraday-style readers, for code written against the Faraday-derived
    # ResourceNotFound, ConflictError and UnprocessableEntityError of 0.5.0.
    alias response_status  http_status
    alias response_headers http_headers
    alias response_body    http_body

    # Builds an error from a Faraday error, carrying over its HTTP response.
    # The Faraday error becomes `cause` when raised from a rescue block.
    def self.from_faraday(error, message = error.message)
      build(message, response_attributes(error)).tap { |e| e.response = error.response }
    end

    # Builds an error from a Resteze::Response, for APIs that report failures
    # inside a successful HTTP response (see Response.body_error).
    def self.from_response(response, message = nil)
      data = response.data
      attributes = { http_status: response.http_status, http_body: response.http_body,
                     http_headers: response.http_headers || {},
                     json_body: (data if data.is_a?(Hash) || data.is_a?(Array)) }

      build(message, attributes).tap { |e| e.response = response }
    end

    # Types with a different constructor signature override this.
    def self.build(message, attributes)
      new(message, **attributes)
    end

    def self.response_attributes(error)
      headers = error.response_headers || {}
      body    = error.response_body

      { http_status: error.response_status, http_body: body, http_headers: headers,
        json_body: parsed_body(body, status: error.response_status, headers: headers) }
    end

    def self.parsed_body(body, status:, headers:)
      data = Resteze::Response.parse_body(body, status:, headers:)
      data if data.is_a?(Hash) || data.is_a?(Array)
    rescue StandardError
      nil
    end
    private_class_method :response_attributes, :parsed_body

    # def initialize(message = nil, http_status: nil, http_body: nil, json_body: nil,
    #                http_headers: nil, code: nil)
    def initialize(message = nil, **kwargs)
      super(**kwargs)
      @message      = message
      @http_status  = kwargs[:http_status]
      @http_body    = kwargs[:http_body]
      @http_headers = kwargs.fetch(:http_headers, {})
      @json_body    = kwargs[:json_body]
      @code         = kwargs[:code]
    end

    def to_s
      status = "HTTP #{@http_status}:" if @http_status.present?
      [status, message].compact.join(" ")
    end

    # Case-insensitive header lookup; http_headers may be a plain Hash or a
    # Faraday::Utils::Headers.
    def header(name)
      RateLimit.header_value(http_headers, name)
    end

    # Whatever the module's RateLimiter makes of this error (see
    # Resteze::RateLimiter#rate_limit), or nil.
    def rate_limit
      @rate_limit ||= api_module.try(:rate_limiter)&.rate_limit(self)
    end
  end

  # Behaviour for the error types that add more than a name. Every API module
  # gets its own subclasses of its own Error (see Errors.define), so type
  # behaviour lives in modules that each of those subclasses includes.
  module InvalidRequest
    attr_accessor :param

    module ClassMethods
      def build(message, attributes)
        new(message, nil, **attributes)
      end
    end

    def self.included(base)
      base.extend(ClassMethods)
    end

    def initialize(message, param, **keyword_args)
      super(message, **keyword_args)
      @param = param
    end
  end

  module RateLimited
    # Seconds to wait before retrying, from the HTTP Retry-After header.
    # Accepts delay-seconds or an HTTP-date; nil when absent or unparseable.
    # Redefine on MyApi::RateLimitError for an API that signals the wait
    # some other way.
    def retry_after
      value = header("Retry-After")
      return if value.blank?
      return Integer(value) if value.to_s.match?(/\A\d+\z/)

      [(Time.httpdate(value.to_s) - Time.now).ceil, 0].max
    rescue ArgumentError
      nil
    end
  end

  module Errors
    # Error type name => behaviour module. Resteze and every API module that
    # includes it define one subclass of their own Error per entry, so
    # `rescue MyApi::Error` catches every error the client raises and errors
    # from one API are never caught by rescue clauses written for another.
    TYPES = {
      InvalidRequestError: InvalidRequest,
      AuthenticationError: nil,
      ApiConnectionError: nil,
      ApiError: nil,
      RateLimitError: RateLimited,
      ResourceNotFound: nil,
      ConflictError: nil,
      UnprocessableEntityError: nil
    }.freeze

    def self.define(namespace, base)
      TYPES.each do |name, behaviour|
        next if namespace.const_defined?(name, false)

        namespace.const_set(name, Class.new(base) { include behaviour if behaviour })
      end
    end
  end

  Errors.define(self, Error)
end
