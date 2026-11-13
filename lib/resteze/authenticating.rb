module Resteze
  # Drives the API module's Authenticator through the request lifecycle
  # (see Resteze::Authenticator). Prepended on Client inside RateLimiting
  # and outside Instrumentation, so a retry with a renewed credential is
  # one attempt to the limiter and two events to instrumentation.
  module Authenticating
    def execute_request(method, path, **options)
      authenticator = api_module.authenticator
      attempt = 0
      begin
        request = Authenticator::Request.new(http_method: method, path:,
                                             headers: options.fetch(:headers, {}).dup,
                                             params: options.fetch(:params, {}).dup,
                                             query: options.fetch(:query, {}).dup)
        authenticator.apply(request)
        super(method, path, **options, headers: request.headers, params: request.params, query: request.query)
      rescue api_module::AuthenticationError => e
        raise unless authenticator.refresh?(e, attempt += 1)

        retry
      end
    end
  end
end
