module Resteze
  class Client
    include Resteze::ApiModule

    def self.user_agent
      [
        "Ruby/#{RUBY_VERSION}",
        "Faraday/#{Faraday::VERSION} (#{faraday_adapter})",
        "Resteze/#{Resteze::VERSION}",
        "#{api_module}/#{api_module::VERSION}"
      ].join(" ")
    end

    def self.proxy_options
      return if api_module.try(:proxy).blank?

      Faraday::ProxyOptions.from(api_module.proxy)
    end

    def self.client_name
      @client_name ||= to_s.underscore
    end

    def self.active_client
      Thread.current[client_name] || default_client
    end

    def self.default_client
      Thread.current["#{client_name}_default_client"] ||= new(default_connection)
    end

    def self.default_connection
      Thread.current["#{client_name}_default_connection"] ||= Faraday.new do |conn|
        conn.use Faraday::Request::UrlEncoded
        conn.use api_module::Middleware::RaiseError
        conn.adapter Faraday.default_adapter
      end
    end

    def self.faraday_adapter
      @faraday_adapter ||= default_connection.builder.adapter.name.demodulize.underscore
    end

    # This can be overriden to customize
    def self.api_url(path = "")
      [api_module.api_base.chomp("/".freeze), path].join
    end

    attr_accessor :connection

    delegate :logger,
             :api_url,
             :client_name,
             to: :class

    def initialize(connection = self.class.default_connection)
      self.connection = connection
    end

    def request
      @last_response = nil
      old_client = Thread.current[client_name]
      Thread.current[client_name] = self
      begin
        res = yield
        [res, @last_response]
      ensure
        Thread.current[client_name] = old_client
      end
    end

    # TODO: Look at refactoring this if possible to improve the Abc size
    # rubocop:disable Metrics/AbcSize
    def execute_request(method, path, headers: {}, params: {})
      params = util.objects_to_ids(params)
      body, query_params = process_params(method, params)
      headers = request_headers.merge(util.normalize_headers(headers))
      context = request_log_context(body:, method:, path:, query_params:, headers:)

      http_resp = execute_request_with_rescues(context) do
        connection.run_request(method, api_url(path), body, headers) do |req|
          req.options.open_timeout = api_module.open_timeout
          req.options.timeout      = api_module.read_timeout
          req.options.proxy        = self.class.proxy_options
          req.params               = query_params unless query_params.nil?
        end
      end

      api_module::Response.from_faraday_response(http_resp).tap do |response|
        @last_response = response
      end
    end
    # rubocop:enable Metrics/AbcSize

    protected

    # Override to customize
    def request_headers
      {
        "User-Agent" => self.class.user_agent,
        "Accept" => "application/json",
        "Content-Type" => "application/json"
      }
    end

    private

    def process_params(method, params)
      body = nil
      query_params = nil
      case method.to_s.downcase.to_sym
      when :get, :head, :delete
        query_params = params
      else
        body = params.to_json
      end
      [body, query_params]
    end

    def params_encoder
      self.class.default_connection.options.params_encoder || Faraday::Utils.default_params_encoder
    end

    def request_log_context(method: nil, path: nil, query_params: nil, headers: nil, body: nil)
      RequestLogContext.new.tap do |context|
        context.method       = method
        context.path         = path
        context.query_params = params_encoder.encode(query_params)
        context.headers      = headers
        context.body         = body
      end
    end

    def execute_request_with_rescues(context)
      begin
        request_start = Time.now
        log_request(context)
        resp = yield
        context = context.dup_from_response(resp)
        log_response(context, request_start, resp)
      rescue StandardError => e
        execute_request_rescue_log(e, context, request_start)
        raise e
      end

      resp
    end

    def execute_request_rescue_log(err, context, request_start)
      if err.respond_to?(:response) && err.response
        error_context = context.dup_from_response(err.response)
        log_response(error_context, request_start, err.response)
      else
        log_response_error(context, request_start, err)
      end
    end

    def log_request(context)
      logger.info do
        payload = {
          method: context.method,
          path: context.path
        }
        "#{self.class} API Request: #{payload}"
      end
      logger.debug { request_details_in_http_syntax(context) }
    end

    def log_response(context, request_start, response)
      status = response.respond_to?(:status) ? response.status : response[:status]
      logger.debug { response_details_in_http_syntax(response) }
      logger.info do
        payload = {
          elapsed: Time.now - request_start,
          method: context.method,
          path: context.path,
          status:
        }
        "#{self.class} API Response: #{payload}"
      end
    end

    def log_response_error(context, request_start, err)
      logger.error do
        payload = {
          elapsed: Time.now - request_start,
          error_message: err.message,
          method: context.method,
          path: context.path
        }
        "#{self.class} Request Error: #{payload}"
      end
    end

    def request_details_in_http_syntax(context)
      "#{self.class} Full Request:\n\n".tap do |s|
        s << request_in_http_syntax(context)
        s << headers_in_http_syntax(context.headers)
        s << "\n\n#{context.body}\n" if context.body.present?
      end
    end

    # TODO: Look into refactoring to improve Abc Size
    # rubocop:disable Metrics/AbcSize
    def response_details_in_http_syntax(response)
      status  = response.respond_to?(:status)  ? response.status  : response[:status]
      body    = response.respond_to?(:body)    ? response.body    : response[:body]
      headers = response.respond_to?(:headers) ? response.headers : response[:headers]
      "#{self.class} Full Response:\n\n".tap do |s|
        s << "HTTP/1.1 #{status}\n"
        s << headers_in_http_syntax(headers)
        s << "\n\n"
        s << (body.encoding == Encoding::ASCII_8BIT ? "(Binary Response)" : body)
        s << "\n"
      end
    end
    # rubocop:enable Metrics/AbcSize

    def request_in_http_syntax(context)
      method = context.method.to_s.upcase
      method.tap do |s|
        s << " "
        s << [self.class.api_url(context.path), context.query_params].select(&:present?).join("?")
        s << "\n"
      end
    end

    def headers_in_http_syntax(headers)
      headers.map { |k, v| [k, v].join(": ") }.join("\n")
    end

    class RequestLogContext
      attr_accessor :body, :method, :path, :query_params, :headers

      def dup_from_response(resp)
        return self if resp.nil?

        dup
      end
    end
  end
end
