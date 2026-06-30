# Resteze API Documentation

## Table of Contents
- [Core Concepts](#core-concepts)
- [Basic Setup](#basic-setup)
- [Resource Definition](#resource-definition)
- [Making Requests](#making-requests)
- [Response Handling](#response-handling)
- [Advanced Features](#advanced-features)

## Core Concepts

Resteze provides a framework for building REST API client gems with the following core components:

### ApiModule
The foundation that gets included in your API namespace module. It sets up the infrastructure for your API client.

### ApiResource
Base class for all your API resources. Inherits from `Resteze::Object` (which extends `Hashie::Trash`) providing property management and data transformation capabilities.

### Client
Manages HTTP connections and request execution. Thread-safe and supports connection customization.

### Request
Module that provides request functionality to resources, delegating to the active client.

## Basic Setup

### Creating Your API Module

```ruby
require 'resteze'

module MyApi
  include Resteze
  
  # Basic configuration
  configure do |config|
    config.api_base = 'https://api.example.com/'
    config.open_timeout = 30  # seconds
    config.read_timeout = 60   # seconds
    config.logger = Logger.new($stdout)
    config.proxy = 'http://proxy.example.com:8080'  # optional
  end
end
```

### Custom Configuration Properties

You can add custom configuration properties to your API module:

```ruby
module MyApi
  include Resteze
  
  class << self
    attr_accessor :api_key, :api_secret, :environment
  end
  
  configure do |config|
    config.api_base = 'https://api.example.com/'
    config.api_key = ENV['MY_API_KEY']
    config.api_secret = ENV['MY_API_SECRET']
    config.environment = :production
  end
end
```

## Resource Definition

### Basic Resource

```ruby
module MyApi
  class User < ApiResource
    # Define properties that map to API response fields
    property :id
    property :email
    property :name
    property :created_at
    property :updated_at
  end
end
```

### Resource with Custom Paths

```ruby
module MyApi
  class User < ApiResource
    property :id
    property :email
    
    # Override the resource slug (defaults to pluralized class name)
    def self.resource_slug
      'accounts'  # Use /accounts instead of /users
    end
    
    # Override the entire resource path
    def self.resource_path(id = nil)
      if id
        "/v2/accounts/#{CGI.escape(id.to_s)}"
      else
        "/v2/accounts"
      end
    end
    
    # Custom service path
    def self.service_path
      '/api'
    end
    
    # API version
    def self.api_version
      'v2'
    end
  end
end
```

### Nested Resources

```ruby
module MyApi
  class Comment < ApiResource
    property :id
    property :post_id
    property :content
    property :author
    
    def self.resource_path(id = nil, post_id: nil)
      if post_id
        "/posts/#{post_id}/comments#{id ? "/#{id}" : ""}"
      else
        super(id)
      end
    end
    
    # Retrieve comments for a specific post
    def self.list_by_post(post_id)
      request(:get, resource_path(nil, post_id: post_id))
    end
  end
end
```

## Making Requests

### Retrieving Resources

```ruby
# Get a single resource by ID
user = MyApi::User.retrieve('123')
puts user.email

# With additional parameters
user = MyApi::User.new('123', values: { include: 'profile' })
user.refresh  # Makes the API call

# Refresh existing resource
user.refresh  # Re-fetches from API
```

### Custom Request Methods

```ruby
module MyApi
  class User < ApiResource
    property :id
    property :email
    property :status
    
    # Instance method for custom action
    def activate!
      response = request(
        :post,
        "#{resource_path}/activate",
        params: { send_email: true }
      )
      initialize_from(response.data)
    end
    
    # Class method for custom endpoint
    def self.search(query)
      response = request(
        :get,
        "#{resource_path}/search",
        params: { q: query }
      )
      response.data.map { |attrs| construct_from(attrs) }
    end
    
    # Custom headers
    def update_with_version(version, attributes)
      request(
        :patch,
        resource_path,
        params: attributes,
        headers: { 'If-Match' => version }
      )
    end
  end
end
```

### Direct Request Access

```ruby
# Using the request module directly
MyApi::User.request(:get, '/custom/endpoint', params: { foo: 'bar' })

# Using the client directly
client = MyApi::Client.active_client
response = client.execute_request(
  :post,
  '/api/v1/users',
  headers: { 'X-Custom-Header' => 'value' },
  params: { email: 'user@example.com' }
)
```

## Response Handling

### Response Object

```ruby
response = MyApi::User.request(:get, '/users')

# Access response data
response.data          # Parsed response body
response.status        # HTTP status code
response.headers       # Response headers
response.body          # Raw response body
response.request_id    # Request ID from headers (if present)
```

### Working with Objects

```ruby
user = MyApi::User.retrieve('123')

# Access properties
user.id
user.email
user[:email]  # Hash-style access

# Check if persisted
user.persisted?  # true if has an ID

# Access metadata (fields not defined as properties)
user.resteze_metadata  # Hash of additional fields
user.property_bag      # Hash of undefined properties

# Deep merge data
user.merge_from({ email: 'new@example.com', profile: { name: 'John' } })
```

### Property Transformation

```ruby
module MyApi
  class User < ApiResource
    # Use Hashie transformations
    property :email, from: :email_address
    property :name, from: :full_name
    property :active, from: :is_active, with: ->(v) { v == 'true' }
    
    # Custom transformation method
    property :created_at, transform_with: ->(v) { Time.parse(v) if v }
  end
end
```

## Advanced Features

### Custom Object Keys

When API responses wrap data in a specific key:

```ruby
module MyApi
  # Response format: { "user": { "id": 1, "email": "..." } }
  
  def self.default_object_key(klass)
    klass.name.demodulize.underscore
  end
  
  class User < ApiResource
    property :id
    property :email
    
    # Or override per-class
    def self.object_key
      :account  # Look for data in { "account": {...} }
    end
  end
end
```

### Custom API Keys

Transform property names between Ruby and API formats:

```ruby
module MyApi
  # Convert snake_case to camelCase
  def self.default_api_key(attribute)
    attribute.to_s.camelcase(:lower)
  end
  
  class User < ApiResource
    property :first_name  # Maps to "firstName" in API
    property :last_name   # Maps to "lastName" in API
  end
end
```

### Thread Safety

Resteze uses thread-local storage for client management:

```ruby
# Each thread gets its own client instance
Thread.new do
  MyApi::Client.new(custom_connection).request do
    # All requests in this block use the custom client
    user = MyApi::User.retrieve('123')
  end
end

# Default client is shared within a thread
MyApi::Client.active_client  # Returns thread's active client
MyApi::Client.default_client # Returns thread's default client
```

### Custom Middleware

```ruby
module MyApi
  class Client < Resteze::Client
    def self.default_connection
      @default_connection ||= Faraday.new do |conn|
        # Add custom middleware
        conn.use MyCustomMiddleware
        conn.request :json
        conn.response :json
        conn.use Faraday::Request::UrlEncoded
        conn.use MyApi::Middleware::RaiseError
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
```

### Connection Customization

```ruby
# Create a custom connection
custom_conn = Faraday.new do |conn|
  conn.request :retry, max: 3, interval: 0.5
  conn.request :authorization, 'Bearer', -> { MyApi.api_key }
  conn.adapter :typhoeus  # Use Typhoeus adapter
end

# Use custom connection
client = MyApi::Client.new(custom_conn)
client.request do
  user = MyApi::User.retrieve('123')
end
```

### Logging

```ruby
module MyApi
  configure do |config|
    # Use a custom logger
    config.logger = Logger.new('api.log')
    config.logger.level = Logger::DEBUG  # Show detailed request/response
  end
  
  class Client < Resteze::Client
    # Override logging behavior
    def log_request(context)
      super
      # Add custom logging
      logger.info "Custom: #{context.inspect}"
    end
  end
end
```

### Proxy Support

```ruby
module MyApi
  configure do |config|
    # Simple proxy
    config.proxy = 'http://proxy.example.com:8080'
    
    # Proxy with authentication
    config.proxy = {
      uri: 'http://proxy.example.com:8080',
      user: 'username',
      password: 'password'
    }
  end
end
```