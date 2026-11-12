# Configuration Guide

## Table of Contents
- [Basic Configuration](#basic-configuration)
- [Authentication](#authentication)
- [Environment-based Configuration](#environment-based-configuration)
- [Dynamic Configuration](#dynamic-configuration)
- [Connection Configuration](#connection-configuration)
- [Logging Configuration](#logging-configuration)
- [Proxy Configuration](#proxy-configuration)
- [Rate Limits](#rate-limits)
- [Advanced Configuration Patterns](#advanced-configuration-patterns)

## Basic Configuration

### Minimal Setup

```ruby
require 'resteze'

module MyApi
  include Resteze
  
  configure do |config|
    config.api_base = 'https://api.example.com/'
  end
end
```

### Standard Configuration

```ruby
module MyApi
  include Resteze
  
  configure do |config|
    # API endpoint
    config.api_base = 'https://api.example.com/'
    
    # Timeouts (in seconds)
    config.open_timeout = 30  # Connection timeout
    config.read_timeout = 60  # Read timeout
    
    # Logging
    config.logger = Logger.new($stdout)
    
    # Proxy (optional)
    config.proxy = ENV['HTTP_PROXY']
  end
end
```

### Custom Configuration Properties

```ruby
module MyApi
  include Resteze
  
  # Define custom properties
  class << self
    attr_accessor :api_key,
                  :api_secret,
                  :environment,
                  :rate_limit,
                  :retry_count,
                  :cache_ttl
  end
  
  configure do |config|
    # Standard Resteze config
    config.api_base = 'https://api.example.com/'
    config.open_timeout = 30
    config.read_timeout = 60
    
    # Custom config
    config.api_key = ENV['API_KEY']
    config.api_secret = ENV['API_SECRET']
    config.environment = ENV['API_ENV'] || 'production'
    config.rate_limit = 100  # requests per minute
    config.retry_count = 3
    config.cache_ttl = 300  # 5 minutes
  end
end
```

## Authentication

Each module gets a `MyApi::Authenticator`, a subclass of `Resteze::Authenticator` that does nothing until you choose a scheme with `authenticate_with` on the module. A scheme is a `Resteze::Authenticator::Strategy` subclass; it expects its credential in a conventional module setting, declares that setting on the module when chosen, and reads it on every request, so an initializer fills it through `configure` like any other setting and a rotated value takes effect without a restart. A setting that is still `nil` when a request goes out raises an `ArgumentError` naming it rather than sending an empty credential; `MyApi.authenticator.missing_settings` lists them for a boot-time check.

```ruby
module MyApi
  include Resteze

  authenticate_with :api_key, header: 'X-Api-Key'   # expects MyApi.api_key
end

# config/initializers/my_api.rb
MyApi.configure do |config|
  config.api_key = ENV['MY_API_KEY']
end
```

The convention is a default. Any credential option also takes a Symbol naming a different setting (`value: :partner_key`), a callable (`value: -> { TokenStore.current }`), or a literal. Schemes combine; call `authenticate_with` once per scheme. (`strategy` inside `class Authenticator` is the same thing, for when you are reopening the class anyway to override its lifecycle.)

### Built-in schemes

| Scheme | Expects | Options | Sends |
|---|---|---|---|
| `:api_key` | `api_key` | `value:`, and `header:` (default `X-Api-Key`) or `query:` | the key in that header, or in the query string on every request whatever the method |
| `:basic` | `username`, `password` | `username:`, `password:` | `Authorization: Basic …` |
| `:bearer` | `api_key` | `token:`, `scheme:` (default `Bearer`) | `Authorization: Bearer …`; `scheme: 'Token'` for another prefix |
| `:mtls` | `client_cert`, `client_key`, `client_key_passphrase` | `cert:`, `key:`, `passphrase:`, `ca_file:`, `verify:` | a client certificate on the TLS connection; nothing on the requests |

`cert:` and `key:` for `:mtls` are PEM strings or paths to PEM files, from the settings, a callable, or a literal. A path is read as given when the connection is first built, so make it absolute (`Rails.root.join(...)`); a relative path resolves against whatever the process's working directory happens to be at that moment. The certificate is applied when `Client.default_connection` builds the connection, so an override of that method must pass `connection_options` to Faraday itself.

### The lifecycle

The client calls the authenticator at three points: `connection_options` when the per-thread connection is built (an override of `Client.default_connection` must pass them to Faraday itself), `apply(request)` before every request (with `headers`, `params` and `query` to mutate; `query` always goes in the query string whatever the method), and `refresh?(error, attempt)` after a `MyApi::AuthenticationError`, where returning `true` sends the request once more with a renewed credential.

### Writing a scheme

Subclass `Resteze::Authenticator::Strategy` and implement `apply(request, state)`; add `connection_options` or `refresh?(error, attempt, state)` when needed. A `DEFAULTS` constant whose Symbol values name module settings makes `authenticate_with` declare those settings. `resolve` reads an option whether it is a Symbol (from the module), a callable, or a literal; `resolve!` does the same and raises a clear `ArgumentError` on `nil`. `state` is a hash shared by every thread and every strategy on the authenticator, already under its lock, so a cached credential needs no synchronisation of its own; prefix your keys with the scheme's name. Options after the class go to your constructor.

```ruby
module MyApi
  class SessionToken < Resteze::Authenticator::Strategy
    DEFAULTS = { username: :username, password: :password }.freeze   # the settings this scheme expects

    def initialize(login_url:, username: :username, password: :password)
      super()
      @login_url, @username, @password = login_url, username, password
    end

    def apply(request, state)
      state[:session_token] ||= login
      request.headers['X-Session-Token'] = state[:session_token]
    end

    def refresh?(_error, attempt, state)
      return false if attempt > 1

      state[:session_token] = login
      true
    end

    private

    def login
      body = { username: resolve!(:username, @username), password: resolve!(:password, @password) }.to_json
      JSON.parse(Faraday.post(@login_url, body, 'Content-Type' => 'application/json').body).fetch('token')
    end
  end

  authenticate_with SessionToken, login_url: 'https://api.example.com/login'   # expects MyApi.username and .password
end
```

`Resteze::Authenticator::Strategy.register(:session_token, SessionToken)` gives a scheme a name, so `authenticate_with :session_token` works like a built-in; a gem that ships a scheme registers it this way.

`MyApi.authenticator` is the instance the client uses; assign another to replace it (tests do this to swap credentials) or `nil` to restore the default. `Client#request_headers` remains overridable for headers that are not a credential.

## Environment-based Configuration

### Using Rails Environments

```ruby
module MyApi
  include Resteze
  
  configure do |config|
    case Rails.env
    when 'production'
      config.api_base = 'https://api.example.com/'
      config.logger = Rails.logger
      config.open_timeout = 30
      config.read_timeout = 60
    when 'staging'
      config.api_base = 'https://staging-api.example.com/'
      config.logger = Rails.logger
      config.open_timeout = 45
      config.read_timeout = 90
    when 'development'
      config.api_base = 'http://localhost:3000/'
      config.logger = Logger.new($stdout)
      config.logger.level = Logger::DEBUG
      config.open_timeout = 60
      config.read_timeout = 120
    when 'test'
      config.api_base = 'http://test.local/'
      config.logger = Logger.new(nil)  # Disable logging in tests
      config.open_timeout = 5
      config.read_timeout = 5
    end
  end
end
```

### Using Environment Variables

```ruby
module MyApi
  include Resteze
  
  configure do |config|
    # Required environment variables
    config.api_base = ENV.fetch('MY_API_URL') do
      raise "MY_API_URL environment variable is required"
    end
    
    # Optional with defaults
    config.open_timeout = ENV.fetch('MY_API_OPEN_TIMEOUT', 30).to_i
    config.read_timeout = ENV.fetch('MY_API_READ_TIMEOUT', 60).to_i
    
    # Conditional configuration
    if ENV['MY_API_DEBUG'] == 'true'
      config.logger = Logger.new($stdout)
      config.logger.level = Logger::DEBUG
    else
      config.logger = Logger.new('log/my_api.log')
      config.logger.level = Logger::INFO
    end
    
    # Proxy configuration
    config.proxy = ENV['HTTP_PROXY'] if ENV['HTTP_PROXY']
  end
end
```

### Using Configuration Files

```ruby
# config/my_api.yml
production:
  api_base: "https://api.example.com/"
  api_key: <%= ENV['MY_API_KEY'] %>
  open_timeout: 30
  read_timeout: 60

development:
  api_base: "http://localhost:3000/"
  api_key: "development-key"
  open_timeout: 60
  read_timeout: 120

test:
  api_base: "http://test.local/"
  api_key: "test-key"
  open_timeout: 5
  read_timeout: 5
```

```ruby
# Load configuration from YAML
require 'yaml'
require 'erb'

module MyApi
  include Resteze
  
  # Load config file
  config_file = File.join(Rails.root, 'config', 'my_api.yml')
  config_data = YAML.safe_load(ERB.new(File.read(config_file)).result)
  settings = config_data[Rails.env]
  
  configure do |config|
    settings.each do |key, value|
      config.send("#{key}=", value)
    end
  end
end
```

## Dynamic Configuration

### Runtime Configuration Changes

```ruby
module MyApi
  include Resteze
  
  class << self
    def reconfigure
      yield self if block_given?
    end
    
    def reset_configuration!
      configure do |config|
        config.api_base = default_api_base
        config.open_timeout = 30
        config.read_timeout = 60
        config.logger = Logger.new($stdout)
      end
    end
    
    private
    
    def default_api_base
      'https://api.example.com/'
    end
  end
end

# Usage
MyApi.reconfigure do |config|
  config.api_base = 'https://new-api.example.com/'
  config.api_key = 'new-key'
end

# Reset to defaults
MyApi.reset_configuration!
```

### Per-Request Configuration

```ruby
module MyApi
  class Client < Resteze::Client
    def with_timeout(open: nil, read: nil)
      old_open = api_module.open_timeout
      old_read = api_module.read_timeout
      
      api_module.open_timeout = open if open
      api_module.read_timeout = read if read
      
      yield
    ensure
      api_module.open_timeout = old_open
      api_module.read_timeout = old_read
    end
  end
  
  class User < ApiResource
    # Use custom timeout for slow endpoints
    def self.export_all
      Client.active_client.with_timeout(read: 300) do
        request(:get, "#{resource_path}/export")
      end
    end
  end
end
```

### Multi-tenant Configuration

```ruby
module MyApi
  include Resteze
  
  class << self
    def for_tenant(tenant_id)
      Thread.current[:my_api_tenant] = tenant_id
      yield
    ensure
      Thread.current[:my_api_tenant] = nil
    end
    
    def current_tenant
      Thread.current[:my_api_tenant]
    end
  end
  
  class Client < Resteze::Client
    def request_headers
      headers = super
      if api_module.current_tenant
        headers['X-Tenant-ID'] = api_module.current_tenant
      end
      headers
    end
    
    def self.api_url(path = "")
      base = if api_module.current_tenant
        "https://#{api_module.current_tenant}.api.example.com/"
      else
        api_module.api_base
      end
      [base.chomp("/"), path].join
    end
  end
end

# Usage
MyApi.for_tenant('acme') do
  user = MyApi::User.retrieve('123')  # Uses acme.api.example.com
end
```

## Connection Configuration

### Faraday Connection Setup

```ruby
module MyApi
  class Client < Resteze::Client
    def self.default_connection
      @default_connection ||= Faraday.new do |conn|
        # Request middleware (order matters!)
        conn.request :json  # Encode request bodies as JSON
        conn.request :retry, max: 3, interval: 0.5  # Retry failed requests
        conn.request :authorization, 'Bearer', -> { api_module.api_key }
        
        # Response middleware
        conn.response :json, content_type: /\bjson$/  # Parse JSON responses
        conn.response :logger, api_module.logger, bodies: true  # Log requests
        
        # Error handling
        conn.use Middleware::RaiseError
        
        # Adapter (must be last)
        conn.adapter :net_http_persistent  # Use persistent connections
      end
    end
  end
end
```

### SSL/TLS Configuration

```ruby
module MyApi
  class Client < Resteze::Client
    def self.default_connection
      @default_connection ||= Faraday.new(ssl: ssl_options) do |conn|
        conn.use Middleware::RaiseError
        conn.adapter Faraday.default_adapter
      end
    end
    
    private
    
    def self.ssl_options
      {
        # Certificate verification
        verify: true,  # Verify SSL certificates
        
        # Client certificates
        client_cert: OpenSSL::X509::Certificate.new(File.read('client.crt')),
        client_key: OpenSSL::PKey::RSA.new(File.read('client.key')),
        
        # CA bundle
        ca_file: '/path/to/ca_bundle.pem',
        
        # Minimum TLS version
        version: :TLSv1_2,
        
        # Cipher suites
        ciphers: 'HIGH:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!SRP:!CAMELLIA'
      }
    rescue => e
      Rails.logger.error "Failed to load SSL certificates: #{e.message}"
      { verify: true }  # Fall back to default verification
    end
  end
end
```

### Custom Adapters

```ruby
module MyApi
  class Client < Resteze::Client
    def self.default_connection
      @default_connection ||= Faraday.new do |conn|
        conn.use Middleware::RaiseError
        
        # Choose adapter based on environment
        case Rails.env
        when 'production'
          # Use Typhoeus for better performance
          conn.adapter :typhoeus
        when 'test'
          # Use test adapter for testing
          conn.adapter :test do |stub|
            stub.get('/users/123') { [200, {}, { id: 123 }.to_json] }
          end
        else
          # Default adapter
          conn.adapter Faraday.default_adapter
        end
      end
    end
  end
end
```

## Logging Configuration

### Custom Logger

```ruby
require 'logger'

module MyApi
  include Resteze
  
  class ApiLogger < Logger
    def format_message(severity, timestamp, progname, msg)
      {
        severity: severity,
        timestamp: timestamp.iso8601,
        service: 'my_api',
        message: msg
      }.to_json + "\n"
    end
  end
  
  configure do |config|
    config.logger = ApiLogger.new('log/my_api.log', 'daily')
    config.logger.level = Rails.env.production? ? Logger::INFO : Logger::DEBUG
  end
end
```

### Structured Logging

```ruby
module MyApi
  class Client < Resteze::Client
    private
    
    def log_request(context)
      logger.info({
        event: 'api_request',
        method: context.method,
        path: context.path,
        headers: sanitize_headers(context.headers),
        params: sanitize_params(context.query_params)
      }.to_json)
    end
    
    def log_response(context, request_start, response)
      logger.info({
        event: 'api_response',
        method: context.method,
        path: context.path,
        status: response.status,
        duration_ms: ((Time.now - request_start) * 1000).round,
        request_id: response.headers['x-request-id']
      }.to_json)
    end
    
    def sanitize_headers(headers)
      headers.transform_values do |value|
        value.to_s.include?('Bearer') ? '[REDACTED]' : value
      end
    end
    
    def sanitize_params(params)
      params.transform_values do |value|
        sensitive_param?(value) ? '[REDACTED]' : value
      end
    end
    
    def sensitive_param?(value)
      value.to_s.match?(/password|token|secret|key/i)
    end
  end
end
```

## Proxy Configuration

### Basic Proxy

```ruby
module MyApi
  include Resteze
  
  configure do |config|
    config.proxy = 'http://proxy.example.com:8080'
  end
end
```

### Authenticated Proxy

```ruby
module MyApi
  include Resteze
  
  configure do |config|
    config.proxy = {
      uri: 'http://proxy.example.com:8080',
      user: ENV['PROXY_USER'],
      password: ENV['PROXY_PASSWORD']
    }
  end
end
```

### Conditional Proxy

```ruby
module MyApi
  include Resteze
  
  configure do |config|
    # Only use proxy in production
    if Rails.env.production?
      config.proxy = ENV['HTTP_PROXY']
    end
    
    # Or use different proxies per environment
    config.proxy = case Rails.env
    when 'production'
      'http://prod-proxy.example.com:8080'
    when 'staging'
      'http://staging-proxy.example.com:8080'
    else
      nil  # No proxy for development/test
    end
  end
end
```

## Rate Limits

### The RateLimiter

APIs disagree about rate limits: which headers carry the quota, whether the reset is an epoch or a countdown, whether a 429 is the only signal, whether the client should pace itself or just react. Resteze assumes none of it. `include Resteze` gives your module a `MyApi::RateLimiter`, a subclass of `Resteze::RateLimiter` whose every method is a no-op, and the client calls one instance of it, shared by every thread, at fixed points in each request:

| Called | When | Default |
|---|---|---|
| `before_request(method, path, params:, headers:)` | before sending | waits for the strategy, if one is configured |
| `track(response_or_error)` | after every `Response` and every `MyApi::Error` | lets the strategy learn from the API |
| `retry?(error, attempt)` | after a `MyApi::RateLimitError`; `attempt` starts at 1 | `false` |
| `retry_after(error)` | before a retry | the error's `Retry-After` |
| `rate_limit(response_or_error)` | when `rate_limit` is read on a response or error | the strategy's view, else `nil` |

The instance is `MyApi.rate_limiter`; assign one to replace it. Each attempt of a retried request is logged and instrumented on its own.

### Choosing a strategy

The four common algorithms are built in. Pick one with `strategy` in your module's `RateLimiter`:

```ruby
module Braze
  class RateLimiter
    strategy :fixed_window, limit: 250_000, window: 3600, headers: true
  end
end
```

| Strategy | Options | Behaviour |
|---|---|---|
| `:fixed_window` | `limit:`, `window:` seconds, `headers:`, `reset:` | At most `limit` requests per window, windows aligned to the first request. With `headers: true` the budget and window follow the API's `X-RateLimit-Limit`, `-Remaining` and `-Reset` headers, which is how Braze and JD Power report theirs; pass a Hash to name other headers, and `reset: :seconds` when the reset header is a countdown rather than a time. `limit:` may be omitted when the API sends it, or sends only the remaining count. Syncing is conservative: within a window the lower of the local and reported remaining counts wins, since requests admitted after the server answered are not in its number yet; a reset beyond the local window starts a fresh one; non-finite or far-future resets are not trusted |
| `:sliding_window` | `limit:`, `window:` seconds | At most `limit` requests in any trailing window. Exact; memory bounded by `limit` |
| `:token_bucket` | `capacity:`, `refill_rate:` per second | Bursts up to `capacity`, then paced at the refill rate |
| `:leaky_bucket` | `capacity:`, `leak_rate:` per second | Smooths bursts into a steady rate; a full bucket waits for room |

With a strategy, `before_request` waits until the request fits, outside the lock so one thread's wait never blocks another's bookkeeping, and `rate_limit` on any response or error returns a `Resteze::RateLimit` (`limit`, `remaining`, `reset`, `exhausted?`) of the strategy's current view. For your own algorithm, subclass `Resteze::RateLimiter::Strategy` and pass the class to `strategy`; options after it go to your constructor. `acquire(state, now)` is required: record one request in `state` and return `0`, or record nothing and return the seconds until one could be admitted. `observe(state, response, now)` and `describe(state, now)` are optional. `state` is the limiter's hash, already under its lock, and the strategy itself must stay stateless. A daily quota aligned to midnight UTC:

```ruby
module MyApi
  class DailyQuota < Resteze::RateLimiter::Strategy
    DAY = 86_400

    def initialize(limit:)
      super()
      @limit = limit
    end

    def acquire(state, now)
      roll(state, now)
      return (state[:day_started] + DAY) - now if state[:count] >= @limit

      state[:count] += 1
      0
    end

    def observe(state, response, now)
      data = response.respond_to?(:data) ? response.data : response.json_body
      return unless data.is_a?(Hash) && data[:calls_remaining]

      roll(state, now)
      state[:count] = @limit - data[:calls_remaining].to_i
    end

    def describe(state, now)
      roll(state, now)
      Resteze::RateLimit.new(limit: @limit, remaining: @limit - state[:count], reset: state[:day_started] + DAY)
    end

    private

    def roll(state, now)
      today = now - (now % DAY)
      return if state[:day_started] == today

      state[:day_started] = today
      state[:count]       = 0
    end
  end

  class RateLimiter
    strategy DailyQuota, limit: 10_000
  end
end
```

### Reacting to a 429

A strategy keeps you under the limit; `retry?` and `retry_after` say what to do when the API disagrees. Override them alongside, or instead of, a strategy:

```ruby
module Braze
  class RateLimiter
    strategy :fixed_window, limit: 250_000, window: 3600, headers: true

    def retry?(_error, attempt)
      attempt <= 3
    end
  end
end
```

`retry_after` reads the HTTP `Retry-After` header, accepting delay-seconds or an HTTP-date. For an API that signals the wait another way, override it; `header` does a case-insensitive lookup on the error:

```ruby
def retry_after(error)
  error.header('X-Retry-In')&.to_i || super
end
```

### Waiting without blocking

With a strategy, `before_request` waits in the calling thread by default (`on_wait: :sleep`). A background job would often rather give the thread back and reschedule itself. `on_wait: :raise` makes the limiter raise `MyApi::RateLimitError` instead of waiting, with the computed wait in `retry_after` and no `http_status`, since nothing was sent. An error raised this way never goes through `retry?`; it is a refusal, not a failed attempt.

```ruby
module Braze
  class RateLimiter
    strategy :fixed_window, limit: 250_000, window: 3600, headers: true, on_wait: :raise
  end
end

class TrackEventsJob
  include Sidekiq::Job

  sidekiq_retry_in do |_count, exception|
    exception.respond_to?(:retry_after) ? (exception.retry_after || 60) : :default
  end

  def perform(events)
    Braze::User.track(events:)   # a spent budget, or a 429, raises; Sidekiq reschedules
  end
end
```

The same option is accepted by the constructor, `MyApi::RateLimiter.new(on_wait: :raise)`, and `RateLimitError.new(message, retry_after: seconds)` builds such an error by hand. Under `on_wait: :raise` a retry decided by `retry?` is not slept either: the 429 itself is raised, with its `retry_after`, so both cases reach the job the same way.

Every wait, whether from a strategy or before a retry, is clamped to `max_wait` seconds, one hour by default. A `Retry-After` or reset header that is absurd, non-finite or malicious therefore costs at most one `max_wait`, never a thread parked for a year or a crash on `sleep(Infinity)`. Set it alongside `on_wait:` in `strategy`, or in the constructor:

```ruby
strategy :fixed_window, limit: 1000, window: 60, max_wait: 120
```

### Overriding the lifecycle

Any method can be overridden; call `super` to keep the strategy's behaviour. State belongs in the limiter's mutex-guarded hash, never in instance variables, so a subclass stays thread-safe without doing anything: `state` returns a snapshot, `update_state` merges values, and `synchronize { |state| ... }` yields the live hash for read-modify-write sequences.

```ruby
module Braze
  class RateLimiter
    strategy :fixed_window, limit: 250_000, window: 3600, headers: true

    def before_request(method, path, **)
      raise RateLimitError, "budget reserved for exports" if path.start_with?("/users/export") && state[:remaining].to_i < 1000

      super
    end

    def track(response)
      super
      update_state(remaining: response.rate_limit&.remaining)
    end
  end
end
```

`Resteze::RateLimit.from_headers(headers, names = {})` remains available as a helper for reading the three-header shape by hand.

### Retrying after a 429

Resteze retries a 429 only when your `RateLimiter`'s `retry?` says so. For retries handled below the limiter, with backoff and per-status rules, add the [`faraday-retry`](https://github.com/lostisland/faraday-retry) gem (it is not a Resteze dependency) and place it **after** `RaiseError` in the stack. That puts it closer to the adapter, so it sees the raw 429 and retries before `RaiseError` turns the final answer into an error. `retry_statuses: [429]` makes it honor `Retry-After` automatically.

```ruby
require 'faraday/retry'

module MyApi
  class Client < Resteze::Client
    def self.default_connection
      Thread.current["#{client_name}_default_connection"] ||= Faraday.new do |conn|
        conn.use Faraday::Request::UrlEncoded
        conn.use Middleware::RaiseError
        conn.request :retry,
                     max: 3,
                     interval: 0.5,
                     backoff_factor: 2,
                     retry_statuses: [429],
                     methods: %i[get post]   # POST is not retried by default; add it only
                                             # where the API treats a 429 as "not processed"
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
```

For an API that signals the wait through a non-standard header, pass `rate_limit_retry_header:` and `rate_limit_reset_header:`, with a `header_parser_block:` to convert the value into seconds. See the faraday-retry README.

## Advanced Configuration Patterns

### Configuration with Validation

```ruby
module MyApi
  include Resteze
  
  class Configuration
    REQUIRED_SETTINGS = %i[api_base api_key].freeze
    VALID_ENVIRONMENTS = %w[production staging development test].freeze
    
    def self.validate!(config)
      REQUIRED_SETTINGS.each do |setting|
        value = config.send(setting)
        if value.nil? || value.to_s.empty?
          raise "Configuration error: #{setting} is required"
        end
      end
      
      # Validate API base URL
      unless config.api_base =~ URI::DEFAULT_PARSER.make_regexp
        raise "Configuration error: api_base must be a valid URL"
      end
      
      # Validate environment
      if config.respond_to?(:environment)
        unless VALID_ENVIRONMENTS.include?(config.environment)
          raise "Configuration error: invalid environment '#{config.environment}'"
        end
      end
      
      # Validate timeouts
      if config.open_timeout <= 0 || config.read_timeout <= 0
        raise "Configuration error: timeouts must be positive"
      end
    end
  end
  
  configure do |config|
    config.api_base = ENV['MY_API_URL']
    config.api_key = ENV['MY_API_KEY']
    config.open_timeout = 30
    config.read_timeout = 60
    
    # Validate configuration
    Configuration.validate!(config)
  end
end
```

### Feature Flags Configuration

```ruby
module MyApi
  include Resteze
  
  class << self
    attr_accessor :features
    
    def feature_enabled?(feature)
      features && features[feature] == true
    end
  end
  
  configure do |config|
    config.api_base = 'https://api.example.com/'
    
    # Feature flags
    config.features = {
      caching: Rails.env.production?,
      retry: true,
      circuit_breaker: Rails.env.production?,
      detailed_logging: Rails.env.development?,
      batch_requests: true
    }
  end
  
  class Client < Resteze::Client
    def execute_request(method, path, **options)
      # Use feature flags
      if api_module.feature_enabled?(:caching) && method == :get
        cached_request(method, path, **options)
      else
        super
      end
    end
    
    private
    
    def cached_request(method, path, **options)
      cache_key = "#{path}:#{options.hash}"
      Rails.cache.fetch(cache_key, expires_in: 5.minutes) do
        super(method, path, **options)
      end
    end
  end
end
```

### Configuration Registry

```ruby
module MyApi
  include Resteze
  
  class ConfigurationRegistry
    def self.configurations
      @configurations ||= {}
    end
    
    def self.register(name, &block)
      configurations[name] = block
    end
    
    def self.apply(name)
      config_block = configurations[name]
      raise "Unknown configuration: #{name}" unless config_block
      
      MyApi.configure(&config_block)
    end
  end
  
  # Register configurations
  ConfigurationRegistry.register(:production) do |config|
    config.api_base = 'https://api.example.com/'
    config.api_key = ENV['PROD_API_KEY']
    config.open_timeout = 30
    config.read_timeout = 60
  end
  
  ConfigurationRegistry.register(:development) do |config|
    config.api_base = 'http://localhost:3000/'
    config.api_key = 'dev-key'
    config.open_timeout = 60
    config.read_timeout = 120
    config.logger = Logger.new($stdout)
    config.logger.level = Logger::DEBUG
  end
  
  # Apply configuration
  ConfigurationRegistry.apply(Rails.env.to_sym)
end
```