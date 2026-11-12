module Resteze
  module Instrumentation
    def execute_request(method, path, ...)
      payload = { method: method, path: path, api_module: api_module.name }

      ActiveSupport::Notifications.instrument("request.#{api_module::INSTRUMENTATION_KEY}", payload) do
        super.tap do |response|
          payload[:status]     = response.http_status
          payload[:request_id] = response.request_id
          instrument_rate_limit(payload, response)
        end
      rescue StandardError => e
        instrument_error_response(payload, e)
        raise
      end
    end

    private

    # The limiter's view of the quota after this exchange, when it has one,
    # so subscribers can gauge remaining calls from the events they already
    # receive.
    def instrument_rate_limit(payload, response_or_error)
      return unless response_or_error.respond_to?(:rate_limit)

      view = response_or_error.rate_limit
      payload[:rate_limit] = view.to_h if !view.nil? && view.respond_to?(:to_h)
    end

    # An error raised by the middleware stack usually carries the HTTP response
    # that produced it. Surface its status and request id the same way a
    # successful response would, so subscribers can bucket by status code.
    def instrument_error_response(payload, error)
      instrument_rate_limit(payload, error)
      status, headers = error_response_details(error)
      return if status.nil?

      payload[:status]     = status
      payload[:request_id] = headers&.[]("Request-Id")
    end

    def error_response_details(error)
      case error
      when Faraday::Error then [error.response_status, error.response_headers]
      when Resteze::Error then [error.http_status, error.http_headers]
      end
    end
  end
end
