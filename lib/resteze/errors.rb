module Resteze
  class Error < StandardError
    attr_accessor :response
    attr_reader   :message, :code, :http_body, :http_headers, :http_status, :json_body

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
  end

  class InvalidRequestError < Error
    attr_accessor :param

    def initialize(message, param, **keyword_args)
      super(message, **keyword_args)
      @param = param
    end
  end

  class AuthenticationError < Error; end

  class ApiConnectionError < Error; end

  class ApiError < Error; end
end
