module Resteze
  class Response
    include Resteze::ApiModule

    OK = 200
    attr_accessor :data, :http_body, :http_headers, :http_status, :request_id

    def self.from_faraday_response(faraday_response)
      new.tap do |response|
        response.http_body    = faraday_response.body
        response.http_headers = faraday_response.headers
        response.http_status  = faraday_response.status
        response.request_id   = faraday_response.headers["Request-Id"]

        response.data = parse_body(
          faraday_response.body,
          status: response.http_status,
          headers: response.http_headers
        )

        error = body_error(response)
        raise error if error
      end
    end

    # Override in MyApi::Response for APIs that report failures inside a
    # successful HTTP response. Receives the parsed Response after the
    # status-based middleware has accepted it; return an exception to raise
    # it, or nil to accept the response.
    #
    #   module MyApi
    #     class Response
    #       def self.body_error(response)
    #         data = response.data
    #         return unless data.is_a?(Hash) && data[:errors].present?
    #
    #         ApiError.from_response(response, data[:message])
    #       end
    #     end
    #   end
    def self.body_error(_response)
      nil
    end

    def self.batch_response?(headers)
      headers["Content-Type".freeze].to_s.include?("boundary=batchresponse".freeze)
    end

    def self.parse_body(body, status: nil, headers: {})
      return body if body.blank? || unparsable_body?(status:, headers:)

      type = mime_type(headers)&.symbol || :json
      case type
      when :json
        JSON.parse(body, symbolize_names: true)
      when :xml
        Hash.from_xml(body).deep_symbolize_keys
      else
        body
      end
    end

    def self.unparsable_body?(status:, headers:)
      status.to_i == 204 || (300..399).cover?(status.to_i) || batch_response?(headers)
    end

    def self.mime_type(headers = {})
      mime_type = headers.transform_keys(&:downcase)["content-type"].to_s.split(";").first.to_s.strip
      Mime::LOOKUP[mime_type] || Mime::Type.lookup_by_extension(:json)
    end

    # Exactly 200 OK. Use #success? for the whole 2xx range.
    def ok?
      http_status == OK
    end

    # Any 2xx status, matching Faraday::Response#success?.
    def success?
      (200..299).cover?(http_status)
    end

    # Whatever the module's RateLimiter makes of this response (see
    # Resteze::RateLimiter#rate_limit), or nil.
    def rate_limit
      @rate_limit ||= api_module.try(:rate_limiter)&.rate_limit(self)
    end
  end
end
