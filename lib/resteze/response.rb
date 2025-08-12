module Resteze
  class Response
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
      end
    end

    def self.batch_response?(headers)
      headers["Content-Type".freeze].to_s.include?("boundary=batchresponse".freeze)
    end

    def self.parse_body(body, status: nil, headers: {})
      return body if unparsable_body?(status:, headers:)

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

    def ok?
      http_status == OK
    end
  end
end
