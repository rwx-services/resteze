module Resteze
  module Middleware
    # Maps Faraday's errors onto the API module's namespaced hierarchy so a
    # consumer can `rescue MyApi::Error` and catch everything the client
    # raises. 404, 409 and 422 keep their Faraday-derived namespaced classes
    # for compatibility; everything else becomes a subclass of MyApi::Error.
    class RaiseError < Faraday::Response::RaiseError
      include Resteze::ApiModule

      CONNECTION_ERRORS = [Faraday::ConnectionFailed, Faraday::TimeoutError, Faraday::SSLError].freeze

      # Faraday error class => namespaced error type. Order matters: the first
      # entry the error is_a? wins, so specific classes come before ClientError.
      STATUS_ERRORS = [
        [Faraday::UnauthorizedError,   :AuthenticationError],
        [Faraday::ForbiddenError,      :AuthenticationError],
        [Faraday::TooManyRequestsError, :RateLimitError],
        [Faraday::BadRequestError,     :InvalidRequestError],
        [Faraday::ClientError,         :ApiError],
        [Faraday::ServerError,         :ApiError]
      ].freeze

      # Adapter-level failures never reach on_complete, so catch them here.
      def call(env)
        super
      rescue *CONNECTION_ERRORS => e
        raise api_module::ApiConnectionError.from_faraday(e)
      end

      def on_complete(env)
        super
      rescue Faraday::ConflictError => e
        raise api_module::ConflictError.new(e, e.response)
      rescue Faraday::UnprocessableEntityError => e
        raise api_module::UnprocessableEntityError.new(e, e.response)
      rescue Faraday::ResourceNotFound => e
        raise api_module::ResourceNotFound.new(e, e.response)
      rescue Faraday::Error => e
        raise mapped_error(e)
      end

      private

      def mapped_error(error)
        _, type = STATUS_ERRORS.find { |faraday_class, _| error.is_a?(faraday_class) }
        return error unless type

        api_module.const_get(type).from_faraday(error)
      end
    end
  end
end
