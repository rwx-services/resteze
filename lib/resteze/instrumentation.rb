module Resteze
  module Instrumentation
    def execute_request(method, path, ...)
      payload = { method: method, path: path, api_module: api_module.name }

      ActiveSupport::Notifications.instrument("request.#{api_module::INSTRUMENTATION_KEY}", payload) do
        super.tap do |response|
          payload[:status]     = response.http_status
          payload[:request_id] = response.request_id
        end
      rescue StandardError => e
        instrument_error_response(payload, e)
        raise
      end
    end

    private

    # An error raised by the middleware stack usually carries the HTTP response
    # that produced it. Surface its status and request id the same way a
    # successful response would, so subscribers can bucket by status code.
    def instrument_error_response(payload, error)
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
