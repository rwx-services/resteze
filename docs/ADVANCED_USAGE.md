# Advanced Usage Guide

## Table of Contents
- [List Operations](#list-operations)
- [Save Operations](#save-operations)
- [Error Handling](#error-handling)
- [Pagination](#pagination)
- [Batch Operations](#batch-operations)
- [Caching](#caching)
- [Authentication Strategies](#authentication-strategies)
- [Testing Your API Client](#testing-your-api-client)

## List Operations

### Including the List Module

```ruby
module MyApi
  class Product < ApiResource
    include List
    
    property :id
    property :name
    property :price
    property :category
  end
end
```

### Basic List Operations

```ruby
# List all products
products = MyApi::Product.list
products.each do |product|
  puts "#{product.name}: $#{product.price}"
end

# List with filters
products = MyApi::Product.list(
  category: 'electronics',
  min_price: 100,
  sort: 'price_asc'
)

# Access list metadata
products.resteze_metadata[:total_count]
products.resteze_metadata[:page]
products.resteze_metadata[:per_page]
```

### Custom List Methods

```ruby
module MyApi
  class Product < ApiResource
    include List
    
    # Override list behavior
    def self.list(filters = {})
      response = request(:get, resource_path, params: filters)
      ListObject.new(response.data).tap do |list|
        list.set_data(response.data[:products])
        list.set_metadata(response.data.except(:products))
      end
    end
    
    # Additional list endpoints
    def self.featured
      response = request(:get, "#{resource_path}/featured")
      response.data.map { |attrs| construct_from(attrs) }
    end
    
    def self.search(query, limit: 10)
      response = request(
        :get, 
        "#{resource_path}/search",
        params: { q: query, limit: limit }
      )
      ListObject.new(response.data)
    end
  end
end
```

### Working with ListObject

```ruby
# ListObject extends Hashie::Array
products = MyApi::Product.list

# Array-like operations
products.count
products.first
products.last
products[0]
products.select { |p| p.price > 100 }
products.map(&:name)

# Access metadata
products.metadata[:total]
products.metadata[:has_more]
products.metadata[:url]

# Iterate with metadata
products.each_with_index do |product, index|
  puts "#{index + 1}. #{product.name}"
end
```

## Save Operations

### Including the Save Module

```ruby
module MyApi
  class Customer < ApiResource
    include Save
    
    property :id
    property :email
    property :name
    property :phone
  end
end
```

### Create and Update Operations

```ruby
# Create a new customer
customer = MyApi::Customer.new
customer.email = 'john@example.com'
customer.name = 'John Doe'
customer.save  # POST to /customers

# Update existing customer
customer = MyApi::Customer.retrieve('123')
customer.phone = '+1234567890'
customer.save  # PATCH/PUT to /customers/123

# Check if it's a new record
customer = MyApi::Customer.new
customer.persisted?  # false
customer.save
customer.persisted?  # true
```

### Custom Save Behavior

```ruby
module MyApi
  class Customer < ApiResource
    include Save
    
    # Override save method
    def save
      if persisted?
        update
      else
        create
      end
    end
    
    # Custom create endpoint
    def create
      response = request(:post, '/v2/customers', params: attributes_for_create)
      initialize_from(response.data)
    end
    
    # Custom update endpoint
    def update
      response = request(:put, resource_path, params: attributes_for_update)
      initialize_from(response.data)
    end
    
    # Validation before save
    def save
      validate!
      super
    rescue ValidationError => e
      errors.add(:base, e.message)
      false
    end
    
    private
    
    def attributes_for_create
      attributes.except(:id, :created_at, :updated_at)
    end
    
    def attributes_for_update
      attributes.slice(:name, :phone)  # Only update specific fields
    end
    
    def validate!
      raise ValidationError, "Email is required" if email.blank?
      raise ValidationError, "Invalid email format" unless email =~ /\A[^@\s]+@[^@\s]+\z/
    end
  end
end
```

### Batch Save Operations

```ruby
module MyApi
  class Customer < ApiResource
    include Save
    
    # Bulk create
    def self.create_batch(customers_data)
      response = request(
        :post,
        "#{resource_path}/batch",
        params: { customers: customers_data }
      )
      response.data.map { |attrs| construct_from(attrs) }
    end
    
    # Bulk update
    def self.update_batch(updates)
      response = request(
        :patch,
        "#{resource_path}/batch",
        params: { updates: updates }
      )
      response.data
    end
  end
end

# Usage
customers = MyApi::Customer.create_batch([
  { email: 'user1@example.com', name: 'User 1' },
  { email: 'user2@example.com', name: 'User 2' }
])
```

## Error Handling

### Built-in Error Classes

```ruby
begin
  user = MyApi::User.retrieve('invalid-id')
rescue MyApi::ResourceNotFound => e
  puts "User not found: #{e.message}"
rescue MyApi::InvalidRequestError => e
  puts "Invalid request: #{e.message}"
  puts "Field: #{e.param}" if e.param
rescue MyApi::ApiConnectionError => e
  puts "Connection failed: #{e.message}"
rescue MyApi::ApiError => e
  puts "API error: #{e.message}"
  puts "Status: #{e.http_status}"
  puts "Response: #{e.response.body}"
end
```

### Custom Error Handling

```ruby
module MyApi
  # Define custom errors
  class RateLimitError < Error; end
  class AuthenticationError < Error; end
  
  # Custom middleware for error handling
  class Middleware::CustomErrorHandler < Faraday::Middleware
    def on_complete(env)
      case env[:status]
      when 429
        raise RateLimitError.new(
          "Rate limit exceeded. Retry after #{env[:response_headers]['retry-after']}",
          http_status: 429,
          response: env
        )
      when 401
        raise AuthenticationError.new(
          "Authentication failed",
          http_status: 401,
          response: env
        )
      end
    end
  end
  
  class Client < Resteze::Client
    def self.default_connection
      @default_connection ||= Faraday.new do |conn|
        conn.use Middleware::CustomErrorHandler
        conn.use Middleware::RaiseError
        conn.adapter Faraday.default_adapter
      end
    end
  end
end
```

### Retry Logic

```ruby
module MyApi
  class Client < Resteze::Client
    def execute_request_with_retry(method, path, **options)
      retries = 0
      begin
        execute_request(method, path, **options)
      rescue ApiConnectionError, RateLimitError => e
        if retries < 3
          retries += 1
          sleep(2 ** retries)  # Exponential backoff
          retry
        else
          raise e
        end
      end
    end
  end
end
```

## Pagination

### Implementing Pagination

```ruby
module MyApi
  class Order < ApiResource
    include List
    
    def self.list(page: 1, per_page: 25, **filters)
      response = request(
        :get,
        resource_path,
        params: filters.merge(page: page, per_page: per_page)
      )
      
      ListObject.new(response.data).tap do |list|
        list.set_data(response.data[:orders])
        list.set_metadata({
          page: response.data[:page],
          per_page: response.data[:per_page],
          total: response.data[:total],
          has_more: response.data[:has_more]
        })
      end
    end
    
    # Auto-pagination helper
    def self.all_pages(**filters)
      Enumerator.new do |yielder|
        page = 1
        loop do
          list = list(page: page, **filters)
          list.each { |item| yielder.yield(item) }
          
          break unless list.metadata[:has_more]
          page += 1
        end
      end
    end
  end
end

# Usage
# Get all orders across all pages
MyApi::Order.all_pages(status: 'completed').each do |order|
  process_order(order)
end

# With lazy evaluation
expensive_orders = MyApi::Order.all_pages.lazy
  .select { |order| order.total > 1000 }
  .take(10)
```

### Cursor-based Pagination

```ruby
module MyApi
  class Event < ApiResource
    include List
    
    def self.list(cursor: nil, limit: 100)
      response = request(
        :get,
        resource_path,
        params: { cursor: cursor, limit: limit }.compact
      )
      
      ListObject.new(response.data).tap do |list|
        list.set_data(response.data[:events])
        list.set_metadata({
          next_cursor: response.data[:next_cursor],
          has_more: response.data[:has_more]
        })
      end
    end
    
    def self.each_batch(limit: 100, &block)
      cursor = nil
      loop do
        batch = list(cursor: cursor, limit: limit)
        yield batch
        
        cursor = batch.metadata[:next_cursor]
        break if cursor.nil?
      end
    end
  end
end
```

## Batch Operations

### Parallel Requests

```ruby
require 'parallel'

module MyApi
  class User < ApiResource
    def self.fetch_multiple(ids)
      Parallel.map(ids, in_threads: 5) do |id|
        begin
          retrieve(id)
        rescue ResourceNotFound
          nil
        end
      end.compact
    end
    
    def self.update_multiple(updates)
      Parallel.map(updates, in_threads: 5) do |id, attrs|
        user = retrieve(id)
        user.update_attributes(attrs)
        user.save
        user
      end
    end
  end
end
```

### Batch API Endpoints

```ruby
module MyApi
  class Product < ApiResource
    # Batch fetch
    def self.retrieve_batch(ids)
      response = request(
        :post,
        "#{resource_path}/batch/get",
        params: { ids: ids }
      )
      response.data.map { |attrs| construct_from(attrs) }
    end
    
    # Batch delete
    def self.delete_batch(ids)
      request(
        :delete,
        "#{resource_path}/batch",
        params: { ids: ids }
      )
    end
    
    # Batch update
    def self.update_batch(updates)
      # updates = [{ id: 1, price: 99.99 }, { id: 2, price: 149.99 }]
      response = request(
        :patch,
        "#{resource_path}/batch",
        params: { updates: updates }
      )
      response.data[:updated_count]
    end
  end
end
```

## Caching

### Simple Memory Cache

```ruby
module MyApi
  class CachedClient < Client
    def initialize(connection = self.class.default_connection)
      super
      @cache = {}
      @cache_ttl = 300  # 5 minutes
    end
    
    def execute_request(method, path, **options)
      if method == :get && cacheable?(path)
        cache_key = "#{path}:#{options[:params].to_json}"
        cached = @cache[cache_key]
        
        if cached && cached[:expires_at] > Time.now
          return cached[:response]
        end
        
        response = super
        @cache[cache_key] = {
          response: response,
          expires_at: Time.now + @cache_ttl
        }
        response
      else
        super
      end
    end
    
    private
    
    def cacheable?(path)
      path.match?(/\/(products|categories|static_content)/)
    end
  end
end
```

### Redis Cache

```ruby
require 'redis'
require 'json'

module MyApi
  class RedisCache
    def initialize(redis = Redis.new, ttl: 300)
      @redis = redis
      @ttl = ttl
    end
    
    def fetch(key, &block)
      cached = @redis.get(key)
      return JSON.parse(cached, symbolize_names: true) if cached
      
      result = yield
      @redis.setex(key, @ttl, result.to_json)
      result
    end
    
    def clear(pattern = '*')
      keys = @redis.keys("myapi:#{pattern}")
      @redis.del(*keys) unless keys.empty?
    end
  end
  
  class Product < ApiResource
    def self.cache
      @cache ||= RedisCache.new
    end
    
    def self.retrieve(id)
      cache.fetch("myapi:product:#{id}") do
        super
      end
    end
  end
end
```

## Authentication Strategies

### API Key Authentication

```ruby
module MyApi
  configure do |config|
    config.api_key = ENV['MY_API_KEY']
  end
  
  class Client < Resteze::Client
    def request_headers
      super.merge({
        'X-API-Key' => api_module.api_key
      })
    end
  end
end
```

### OAuth 2.0

```ruby
module MyApi
  class << self
    attr_accessor :access_token, :refresh_token, :token_expires_at
  end
  
  class Client < Resteze::Client
    def request_headers
      ensure_valid_token!
      super.merge({
        'Authorization' => "Bearer #{api_module.access_token}"
      })
    end
    
    private
    
    def ensure_valid_token!
      return if api_module.token_expires_at && api_module.token_expires_at > Time.now
      
      refresh_access_token!
    end
    
    def refresh_access_token!
      response = Faraday.post('https://api.example.com/oauth/token') do |req|
        req.body = {
          grant_type: 'refresh_token',
          refresh_token: api_module.refresh_token,
          client_id: ENV['CLIENT_ID'],
          client_secret: ENV['CLIENT_SECRET']
        }
      end
      
      token_data = JSON.parse(response.body)
      api_module.access_token = token_data['access_token']
      api_module.refresh_token = token_data['refresh_token']
      api_module.token_expires_at = Time.now + token_data['expires_in']
    end
  end
end
```

### HMAC Signature

```ruby
require 'openssl'
require 'base64'

module MyApi
  class Client < Resteze::Client
    def execute_request(method, path, **options)
      timestamp = Time.now.to_i.to_s
      signature = generate_signature(method, path, timestamp, options[:params])
      
      options[:headers] ||= {}
      options[:headers].merge!({
        'X-Timestamp' => timestamp,
        'X-Signature' => signature,
        'X-Client-Id' => api_module.client_id
      })
      
      super
    end
    
    private
    
    def generate_signature(method, path, timestamp, params)
      message = [
        method.to_s.upcase,
        path,
        timestamp,
        params.to_json
      ].join("\n")
      
      hmac = OpenSSL::HMAC.digest('SHA256', api_module.client_secret, message)
      Base64.strict_encode64(hmac)
    end
  end
end
```

## Testing Your API Client

### Using Minitest

```ruby
require 'resteze/testing/minitest'

class MyApiTest < Minitest::Test
  include Resteze::Testing::Minitest
  
  def setup
    configure_api(MyApi) do |config|
      config.api_base = 'http://test.example.com/'
    end
  end
  
  def test_retrieve_user
    stub_api_request(:get, '/users/123').to_return(
      body: { id: 123, email: 'test@example.com' }.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
    
    user = MyApi::User.retrieve('123')
    assert_equal 'test@example.com', user.email
  end
  
  def test_error_handling
    stub_api_request(:get, '/users/999').to_return(status: 404)
    
    assert_raises(MyApi::ResourceNotFound) do
      MyApi::User.retrieve('999')
    end
  end
end
```

### Using RSpec

```ruby
require 'resteze/testing/rspec'

RSpec.describe MyApi::User do
  include Resteze::Testing::RSpec
  
  before do
    configure_api(MyApi) do |config|
      config.api_base = 'http://test.example.com/'
    end
  end
  
  describe '.retrieve' do
    it 'fetches a user by ID' do
      stub_api_request(:get, '/users/123').to_return(
        body: { id: 123, email: 'test@example.com' }.to_json
      )
      
      user = described_class.retrieve('123')
      expect(user.email).to eq('test@example.com')
    end
    
    it 'raises an error for missing users' do
      stub_api_request(:get, '/users/999').to_return(status: 404)
      
      expect { described_class.retrieve('999') }
        .to raise_error(MyApi::ResourceNotFound)
    end
  end
end
```

### VCR Integration

```ruby
require 'vcr'

VCR.configure do |config|
  config.cassette_library_dir = 'test/fixtures/vcr_cassettes'
  config.hook_into :faraday
  config.filter_sensitive_data('<API_KEY>') { MyApi.api_key }
end

class MyApiIntegrationTest < Minitest::Test
  def test_real_api_call
    VCR.use_cassette('user_retrieve') do
      user = MyApi::User.retrieve('123')
      assert_equal 'John Doe', user.name
    end
  end
end
```