# Error Handling Guide

## Table of Contents
- [Error Hierarchy](#error-hierarchy)
- [Built-in Error Types](#built-in-error-types)
- [Error Attributes](#error-attributes)
- [Handling Errors](#handling-errors)
- [Errors Reported in a 2xx Body](#errors-reported-in-a-2xx-body)
- [Custom Error Classes](#custom-error-classes)
- [Middleware Error Handling](#middleware-error-handling)
- [Best Practices](#best-practices)

## Error Hierarchy

Resteze creates a full error hierarchy inside each API module. Every class below is a subclass of that module's own `Error`, so `rescue YourApi::Error` catches everything the client raises, and an error from one API is never caught by a rescue clause written for another.

```
StandardError
└── Resteze::Error
    └── YourApi::Error (base for all of this API's errors)
        ├── YourApi::ApiError            (5xx, and 4xx with no more specific class)
        ├── YourApi::ApiConnectionError  (connection refused, timeout, SSL)
        ├── YourApi::AuthenticationError (401, 403)
        ├── YourApi::InvalidRequestError (400, and requests the client cannot build)
        ├── YourApi::RateLimitError      (429, with #retry_after)
        ├── YourApi::ResourceNotFound    (404)
        ├── YourApi::ConflictError       (409)
        └── YourApi::UnprocessableEntityError (422)

Also namespaced:
└── YourApi::NotImplementedError
```

The `RaiseError` middleware maps every Faraday error onto this hierarchy. The original Faraday error is available as `e.cause`.

## Built-in Error Types

### ApiError
Server-side errors (5xx), plus any 4xx that has no more specific class (for example 405 or 410):

```ruby
begin
  user = MyApi::User.retrieve('123')
rescue MyApi::ApiError => e
  puts "Server error: #{e.message}"
  puts "HTTP Status: #{e.http_status}"
  puts "Response body: #{e.http_body}"
  puts "Parsed body: #{e.json_body.inspect}"   # nil unless the body parsed as JSON or XML
  
  # Retry logic for server errors
  retry if e.http_status >= 500
end
```

### ApiConnectionError
Network and connection failures:

```ruby
begin
  user = MyApi::User.retrieve('123')
rescue MyApi::ApiConnectionError => e
  puts "Connection failed: #{e.message}"
  
  # Common causes:
  # - Network timeout
  # - DNS resolution failure
  # - Connection refused
  # - SSL/TLS errors
  
  # Implement retry with backoff
  sleep(2)
  retry
end
```

### InvalidRequestError
A `400 Bad Request`, or a request the client could not build (for example `refresh` on an object with no id):

```ruby
begin
  user = MyApi::User.create(email: 'invalid')
rescue MyApi::InvalidRequestError => e
  puts "Invalid request: #{e.message}"
  puts "Invalid parameter: #{e.param}" if e.param
  puts "HTTP Status: #{e.http_status}"   # nil when the request was never sent
  
  # Don't retry - fix the request
  log_validation_error(e)
end
```

### AuthenticationError
`401 Unauthorized` and `403 Forbidden`:

```ruby
begin
  user = MyApi::User.retrieve('123')
rescue MyApi::AuthenticationError => e
  puts "Check the API key: #{e.message}"
end
```

### RateLimitError
`429 Too Many Requests`. `retry_after` reads the `Retry-After` header as seconds, accepting either delay-seconds or an HTTP-date, and is `nil` when the header is absent. `rate_limit` exposes your module's `RateLimiter` view of the limit, and that limiter decides whether the client retries (see [Rate Limits](CONFIGURATION.md#rate-limits)):

```ruby
begin
  MyApi::Event.track(events: batch)
rescue MyApi::RateLimitError => e
  e.rate_limit&.remaining   # 0
  sleep(e.retry_after || 1)
  retry
end
```

### ResourceNotFound
404 Not Found errors:

```ruby
begin
  user = MyApi::User.retrieve('non-existent-id')
rescue MyApi::ResourceNotFound => e
  puts "User not found"
  # Handle missing resource
  create_default_user()
end
```

### UnprocessableEntityError
422 Unprocessable Entity (validation errors):

```ruby
begin
  user = MyApi::User.create(email: 'not-an-email')
rescue MyApi::UnprocessableEntityError => e
  puts "Validation failed: #{e.message}"
  
  # Parse validation errors from response
  errors = JSON.parse(e.response[:body])['errors']
  errors.each do |field, messages|
    puts "#{field}: #{messages.join(', ')}"
  end
end
```

### ConflictError
409 Conflict errors:

```ruby
begin
  user = MyApi::User.create(email: 'existing@example.com')
rescue MyApi::ConflictError => e
  puts "Conflict: #{e.message}"
  # Resource already exists
  user = MyApi::User.find_by_email('existing@example.com')
end
```

## Error Attributes

Every subclass of `MyApi::Error` carries the HTTP response that produced it:

```ruby
begin
  MyApi::User.retrieve('123')
rescue MyApi::Error => e
  e.message       # Error message
  e.http_status   # HTTP status code (e.g., 401, 500); nil for connection failures
  e.http_body     # Raw response body
  e.http_headers  # Response headers
  e.header("Retry-After")  # Case-insensitive header lookup
  e.json_body     # Body parsed as JSON or XML, or nil
  e.response      # Faraday's response hash: { status:, headers:, body:, request: }
  e.cause         # The original Faraday error
  e.rate_limit    # MyApi.rate_limiter.rate_limit(e): the strategy's view, or nil

  # For InvalidRequestError
  e.param         # The parameter that caused the error, when known

  # For RateLimitError
  e.retry_after   # Seconds to wait, from Retry-After, or nil
end
```

Every error also answers Faraday's reader names, `response_status`, `response_headers` and `response_body`, as aliases of the `http_` readers. Code written against the earlier Faraday-derived `ResourceNotFound`, `UnprocessableEntityError` and `ConflictError` keeps working.

## Handling Errors

### Basic Error Handling

```ruby
def fetch_user(id)
  MyApi::User.retrieve(id)
rescue MyApi::ResourceNotFound
  nil
rescue MyApi::ApiConnectionError => e
  Rails.logger.error "API connection failed: #{e.message}"
  raise ServiceUnavailableError, "Unable to fetch user"
rescue MyApi::Error => e
  Rails.logger.error "API error: #{e.message}"
  Bugsnag.notify(e)
  raise
end
```

### Comprehensive Error Handling

```ruby
class ApiErrorHandler
  def self.handle
    yield
  rescue MyApi::ResourceNotFound => e
    handle_not_found(e)
  rescue MyApi::UnprocessableEntityError => e
    handle_validation_error(e)
  rescue MyApi::ConflictError => e
    handle_conflict(e)
  rescue MyApi::InvalidRequestError => e
    handle_bad_request(e)
  rescue MyApi::ApiConnectionError => e
    handle_connection_error(e)
  rescue MyApi::ApiError => e
    handle_server_error(e)
  end
  
  private
  
  def self.handle_not_found(error)
    { error: 'Resource not found', status: 404 }
  end
  
  def self.handle_validation_error(error)
    errors = parse_validation_errors(error.response.body)
    { errors: errors, status: 422 }
  end
  
  def self.handle_conflict(error)
    { error: 'Resource already exists', status: 409 }
  end
  
  def self.handle_bad_request(error)
    { error: error.message, param: error.param, status: 400 }
  end
  
  def self.handle_connection_error(error)
    notify_monitoring_service(error)
    { error: 'Service temporarily unavailable', status: 503 }
  end
  
  def self.handle_server_error(error)
    notify_monitoring_service(error)
    { error: 'Internal server error', status: 500 }
  end
  
  def self.parse_validation_errors(body)
    JSON.parse(body)['errors'] rescue {}
  end
  
  def self.notify_monitoring_service(error)
    # Send to error tracking service
    Sentry.capture_exception(error)
  end
end

# Usage
result = ApiErrorHandler.handle { MyApi::User.create(params) }
```

### Retry Logic with Error Handling

```ruby
class RetryableRequest
  MAX_RETRIES = 3
  RETRY_DELAY = 1  # seconds
  
  def self.execute(&block)
    retries = 0
    
    begin
      yield
    rescue MyApi::ApiConnectionError, MyApi::ApiError => e
      if should_retry?(e, retries)
        retries += 1
        delay = RETRY_DELAY * (2 ** (retries - 1))  # Exponential backoff
        
        Rails.logger.warn "Request failed, retrying in #{delay}s (attempt #{retries}/#{MAX_RETRIES})"
        sleep(delay)
        retry
      else
        raise
      end
    end
  end
  
  private
  
  def self.should_retry?(error, retries)
    return false if retries >= MAX_RETRIES
    
    # Retry on connection errors
    return true if error.is_a?(MyApi::ApiConnectionError)
    
    # Retry on specific server errors
    return true if error.is_a?(MyApi::ApiError) && [502, 503, 504].include?(error.http_status)
    
    # Don't retry on client errors
    false
  end
end

# Usage
user = RetryableRequest.execute { MyApi::User.retrieve('123') }
```

## Errors Reported in a 2xx Body

Some APIs answer with a successful HTTP status and put the failure in the body. A messaging API might return `201 Created` with `{"message": "success", "errors": [...]}` when some records in a batch were rejected, and `200 OK` with `{"message": "Invalid API key"}` for others. The status-based middleware cannot see these.

Override `body_error` on your module's `Response`. It receives the parsed `Response` after the middleware has accepted the status. Return an exception to raise it, or `nil` to accept the response. `Error.from_response` builds a namespaced error that carries the status, headers, body and parsed `json_body`, with the `Response` itself as `e.response`:

```ruby
module MyApi
  class Response
    SUCCESS = %w[success queued].freeze

    def self.body_error(response)
      data = response.data
      return unless data.is_a?(Hash)
      return if SUCCESS.include?(data[:message]) && data[:errors].blank?

      ApiError.from_response(response, data[:message] || "errors in response body")
    end
  end
end

begin
  MyApi::User.track(events: batch)
rescue MyApi::ApiError => e
  e.http_status          # 201
  e.json_body[:errors]   # the per-record errors
end
```

The hook runs inside `execute_request`, so the error is instrumented with its status like any other, and `rescue MyApi::Error` catches it. Return a subclass of `ApiError` if callers need to tell partial success apart from a hard failure.

## Custom Error Classes

### Defining Custom Errors

```ruby
module MyApi
  # Custom error classes
  class RateLimitError < Error
    attr_reader :retry_after
    
    def initialize(message, retry_after: nil, **options)
      super(message, **options)
      @retry_after = retry_after
    end
  end
  
  class AuthenticationError < Error
    attr_reader :auth_type
    
    def initialize(message, auth_type: nil, **options)
      super(message, **options)
      @auth_type = auth_type
    end
  end
  
  class ValidationError < InvalidRequestError
    attr_reader :errors
    
    def initialize(message, errors: {}, **options)
      super(message, **options)
      @errors = errors
    end
  end
end
```

### Using Custom Errors

```ruby
module MyApi
  class Client < Resteze::Client
    def execute_request(method, path, **options)
      response = super
      check_rate_limit(response)
      response
    rescue Faraday::ClientError => e
      handle_client_error(e)
    end
    
    private
    
    def check_rate_limit(response)
      remaining = response.headers['x-rate-limit-remaining'].to_i
      if remaining == 0
        reset_time = response.headers['x-rate-limit-reset'].to_i
        retry_after = reset_time - Time.now.to_i
        
        raise RateLimitError.new(
          "Rate limit exceeded",
          retry_after: retry_after,
          http_status: 429,
          response: response
        )
      end
    end
    
    def handle_client_error(error)
      case error.response[:status]
      when 401
        raise AuthenticationError.new(
          "Authentication failed",
          auth_type: error.response[:headers]['www-authenticate'],
          http_status: 401,
          response: error.response
        )
      when 422
        errors = JSON.parse(error.response[:body])['errors'] rescue {}
        raise ValidationError.new(
          "Validation failed",
          errors: errors,
          http_status: 422,
          response: error.response
        )
      else
        raise
      end
    end
  end
end
```

## Middleware Error Handling

### Custom Error Middleware

```ruby
module MyApi
  module Middleware
    class ErrorHandler < Faraday::Middleware
      def on_complete(env)
        case env[:status]
        when 400
          raise_invalid_request(env)
        when 401
          raise_authentication_error(env)
        when 403
          raise_authorization_error(env)
        when 404
          raise_not_found(env)
        when 409
          raise_conflict(env)
        when 422
          raise_validation_error(env)
        when 429
          raise_rate_limit(env)
        when 500..599
          raise_server_error(env)
        end
      end
      
      private
      
      def raise_invalid_request(env)
        body = parse_body(env)
        raise InvalidRequestError.new(
          body['error'] || 'Invalid request',
          param: body['param'],
          http_status: 400,
          response: env
        )
      end
      
      def raise_authentication_error(env)
        raise AuthenticationError.new(
          'Authentication required',
          http_status: 401,
          response: env
        )
      end
      
      def raise_rate_limit(env)
        retry_after = env[:response_headers]['retry-after']
        raise RateLimitError.new(
          'Rate limit exceeded',
          retry_after: retry_after,
          http_status: 429,
          response: env
        )
      end
      
      def raise_server_error(env)
        raise ApiError.new(
          "Server error: #{env[:status]}",
          http_status: env[:status],
          response: env
        )
      end
      
      def parse_body(env)
        JSON.parse(env[:body]) rescue {}
      end
    end
  end
  
  class Client < Resteze::Client
    def self.default_connection
      @default_connection ||= Faraday.new do |conn|
        conn.use Middleware::ErrorHandler
        conn.use Middleware::RaiseError
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
```

### Circuit Breaker Pattern

```ruby
require 'circuit_breaker'

module MyApi
  class CircuitBreakerMiddleware < Faraday::Middleware
    def initialize(app, options = {})
      super(app)
      @circuit = CircuitBreaker.new(
        failure_threshold: options[:failure_threshold] || 5,
        recovery_timeout: options[:recovery_timeout] || 60,
        expected_exception: ApiError
      )
    end
    
    def call(env)
      @circuit.call do
        @app.call(env)
      end
    rescue CircuitBreaker::OpenCircuitError
      raise ApiConnectionError.new(
        "Service circuit breaker is open",
        http_status: 503
      )
    end
  end
  
  class Client < Resteze::Client
    def self.default_connection
      @default_connection ||= Faraday.new do |conn|
        conn.use CircuitBreakerMiddleware,
                 failure_threshold: 3,
                 recovery_timeout: 30
        conn.use Middleware::RaiseError
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
```

## Best Practices

### 1. Always Rescue Specific Errors

```ruby
# Good
begin
  user = MyApi::User.retrieve(id)
rescue MyApi::ResourceNotFound
  return nil
rescue MyApi::ApiConnectionError => e
  log_error(e)
  retry
end

# Bad
begin
  user = MyApi::User.retrieve(id)
rescue => e
  # Too broad, catches unexpected errors
end
```

### 2. Log Errors with Context

```ruby
def fetch_user_with_logging(id)
  MyApi::User.retrieve(id)
rescue MyApi::Error => e
  Rails.logger.error(
    message: "Failed to fetch user",
    user_id: id,
    error_class: e.class.name,
    error_message: e.message,
    http_status: e.http_status,
    response_body: e.response&.body
  )
  raise
end
```

### 3. Implement Graceful Degradation

```ruby
class UserService
  def get_user_with_fallback(id)
    # Try primary API
    fetch_from_api(id)
  rescue MyApi::ApiConnectionError, MyApi::ApiError
    # Fall back to cache
    fetch_from_cache(id)
  rescue MyApi::ResourceNotFound
    # Fall back to default
    User.new(id: id, name: 'Unknown User')
  end
  
  private
  
  def fetch_from_api(id)
    MyApi::User.retrieve(id)
  end
  
  def fetch_from_cache(id)
    Rails.cache.read("user:#{id}")
  end
end
```

### 4. Use Error Monitoring

```ruby
class ErrorNotifier
  def self.configure
    # Configure error monitoring service
    Sentry.init do |config|
      config.before_send = lambda do |event, hint|
        if hint[:exception].is_a?(MyApi::Error)
          event.extra[:api_response] = hint[:exception].response&.body
          event.extra[:http_status] = hint[:exception].http_status
        end
        event
      end
    end
  end
  
  def self.notify(error, context = {})
    Sentry.capture_exception(error, extra: context)
  end
end
```

### 5. Provide User-Friendly Messages

```ruby
class ApiErrorPresenter
  def self.message_for(error)
    case error
    when MyApi::ResourceNotFound
      "The requested item could not be found."
    when MyApi::UnprocessableEntityError
      "Please check your input and try again."
    when MyApi::ConflictError
      "This item already exists."
    when MyApi::ApiConnectionError
      "We're having trouble connecting to our servers. Please try again later."
    when MyApi::ApiError
      "Something went wrong on our end. We've been notified and are working on it."
    else
      "An unexpected error occurred. Please try again."
    end
  end
end
```