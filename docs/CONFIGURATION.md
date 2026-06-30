# Configuration Guide

## Table of Contents
- [Basic Configuration](#basic-configuration)
- [Environment-based Configuration](#environment-based-configuration)
- [Dynamic Configuration](#dynamic-configuration)
- [Connection Configuration](#connection-configuration)
- [Logging Configuration](#logging-configuration)
- [Proxy Configuration](#proxy-configuration)
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