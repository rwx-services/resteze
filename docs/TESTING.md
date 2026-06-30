# Testing Guide

## Table of Contents
- [Testing Setup](#testing-setup)
- [Unit Testing](#unit-testing)
- [Integration Testing](#integration-testing)
- [Mocking and Stubbing](#mocking-and-stubbing)
- [Testing with VCR](#testing-with-vcr)
- [Testing Best Practices](#testing-best-practices)
- [Continuous Integration](#continuous-integration)

## Testing Setup

### Minitest Setup

```ruby
# test/test_helper.rb
require 'minitest/autorun'
require 'minitest/spec'
require 'webmock/minitest'
require 'vcr'
require 'resteze'
require 'resteze/testing/minitest'

# Configure VCR
VCR.configure do |config|
  config.cassette_library_dir = 'test/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.filter_sensitive_data('<API_KEY>') { ENV['API_KEY'] }
  config.filter_sensitive_data('<API_SECRET>') { ENV['API_SECRET'] }
end

# Test API module
module TestApi
  include Resteze
  
  configure do |config|
    config.api_base = 'http://test.example.com/'
    config.api_key = 'test-key'
    config.logger = Logger.new(nil)  # Disable logging in tests
  end
  
  class User < ApiResource
    property :id
    property :email
    property :name
  end
end

# Base test class
class ApiTestCase < Minitest::Test
  include Resteze::Testing::Minitest
  
  def setup
    WebMock.disable_net_connect!(allow_localhost: true)
  end
  
  def teardown
    WebMock.reset!
  end
  
  def stub_api_request(method, path)
    stub_request(method, "#{TestApi.api_base}#{path.sub(/^\//, '')}")
  end
end
```

### RSpec Setup

```ruby
# spec/spec_helper.rb
require 'rspec'
require 'webmock/rspec'
require 'vcr'
require 'resteze'
require 'resteze/testing/rspec'

RSpec.configure do |config|
  config.include Resteze::Testing::RSpec
  
  config.before(:each) do
    WebMock.disable_net_connect!(allow_localhost: true)
  end
  
  config.after(:each) do
    WebMock.reset!
  end
end

# Configure VCR
VCR.configure do |config|
  config.cassette_library_dir = 'spec/fixtures/vcr_cassettes'
  config.hook_into :webmock
  config.configure_rspec_metadata!
  config.filter_sensitive_data('<API_KEY>') { ENV['API_KEY'] }
end

# Shared context for API testing
RSpec.shared_context 'api testing' do
  let(:test_api) do
    Module.new do
      include Resteze
      
      configure do |config|
        config.api_base = 'http://test.example.com/'
        config.api_key = 'test-key'
        config.logger = Logger.new(nil)
      end
    end
  end
  
  def stub_api_request(method, path)
    stub_request(method, "http://test.example.com#{path}")
  end
end
```

## Unit Testing

### Testing Resources

```ruby
# test/api/user_test.rb
class UserTest < ApiTestCase
  def test_retrieve_user
    stub_api_request(:get, '/users/123')
      .to_return(
        status: 200,
        body: { id: 123, email: 'user@example.com', name: 'John Doe' }.to_json,
        headers: { 'Content-Type' => 'application/json' }
      )
    
    user = TestApi::User.retrieve('123')
    
    assert_equal 123, user.id
    assert_equal 'user@example.com', user.email
    assert_equal 'John Doe', user.name
  end
  
  def test_user_not_found
    stub_api_request(:get, '/users/999')
      .to_return(status: 404, body: { error: 'Not found' }.to_json)
    
    assert_raises(TestApi::ResourceNotFound) do
      TestApi::User.retrieve('999')
    end
  end
  
  def test_refresh_user
    user = TestApi::User.new('123')
    
    stub_api_request(:get, '/users/123')
      .to_return(
        status: 200,
        body: { id: 123, email: 'updated@example.com' }.to_json
      )
    
    user.refresh
    assert_equal 'updated@example.com', user.email
  end
end
```

### Testing Lists

```ruby
class UserListTest < ApiTestCase
  def setup
    super
    @list_response = {
      data: [
        { id: 1, email: 'user1@example.com' },
        { id: 2, email: 'user2@example.com' }
      ],
      total: 2,
      page: 1,
      per_page: 10
    }
  end
  
  def test_list_users
    stub_api_request(:get, '/users')
      .with(query: { page: 1, per_page: 10 })
      .to_return(
        status: 200,
        body: @list_response.to_json
      )
    
    users = TestApi::User.list(page: 1, per_page: 10)
    
    assert_equal 2, users.count
    assert_equal 'user1@example.com', users.first.email
    assert_equal 2, users.metadata[:total]
  end
  
  def test_empty_list
    stub_api_request(:get, '/users')
      .to_return(
        status: 200,
        body: { data: [], total: 0 }.to_json
      )
    
    users = TestApi::User.list
    assert_empty users
    assert_equal 0, users.metadata[:total]
  end
end
```

### Testing Save Operations

```ruby
class UserSaveTest < ApiTestCase
  def test_create_user
    stub_api_request(:post, '/users')
      .with(body: { email: 'new@example.com', name: 'New User' })
      .to_return(
        status: 201,
        body: { id: 123, email: 'new@example.com', name: 'New User' }.to_json
      )
    
    user = TestApi::User.new
    user.email = 'new@example.com'
    user.name = 'New User'
    
    refute user.persisted?
    user.save
    
    assert user.persisted?
    assert_equal 123, user.id
  end
  
  def test_update_user
    user = TestApi::User.new('123', values: { email: 'old@example.com' })
    
    stub_api_request(:patch, '/users/123')
      .with(body: { email: 'updated@example.com' })
      .to_return(
        status: 200,
        body: { id: 123, email: 'updated@example.com' }.to_json
      )
    
    user.email = 'updated@example.com'
    user.save
    
    assert_equal 'updated@example.com', user.email
  end
  
  def test_validation_error
    stub_api_request(:post, '/users')
      .with(body: { email: 'invalid' })
      .to_return(
        status: 422,
        body: { 
          error: 'Validation failed',
          errors: { email: ['is invalid'] }
        }.to_json
      )
    
    user = TestApi::User.new
    user.email = 'invalid'
    
    assert_raises(TestApi::UnprocessableEntityError) do
      user.save
    end
  end
end
```

## Integration Testing

### Full Request Cycle Testing

```ruby
class IntegrationTest < ApiTestCase
  def test_complete_user_lifecycle
    # Create user
    stub_api_request(:post, '/users')
      .to_return(
        status: 201,
        body: { id: 123, email: 'test@example.com' }.to_json
      )
    
    user = TestApi::User.new
    user.email = 'test@example.com'
    user.save
    
    assert_equal 123, user.id
    
    # Update user
    stub_api_request(:patch, '/users/123')
      .to_return(
        status: 200,
        body: { id: 123, email: 'updated@example.com' }.to_json
      )
    
    user.email = 'updated@example.com'
    user.save
    
    # Delete user
    stub_api_request(:delete, '/users/123')
      .to_return(status: 204)
    
    response = TestApi::User.request(:delete, user.resource_path)
    assert_equal 204, response.status
  end
  
  def test_pagination_flow
    # First page
    stub_api_request(:get, '/users')
      .with(query: { page: 1, per_page: 2 })
      .to_return(
        body: {
          data: [{ id: 1 }, { id: 2 }],
          has_more: true,
          page: 1
        }.to_json
      )
    
    # Second page
    stub_api_request(:get, '/users')
      .with(query: { page: 2, per_page: 2 })
      .to_return(
        body: {
          data: [{ id: 3 }],
          has_more: false,
          page: 2
        }.to_json
      )
    
    all_users = []
    page = 1
    loop do
      users = TestApi::User.list(page: page, per_page: 2)
      all_users.concat(users)
      break unless users.metadata[:has_more]
      page += 1
    end
    
    assert_equal 3, all_users.count
    assert_equal [1, 2, 3], all_users.map(&:id)
  end
end
```

### Testing Error Recovery

```ruby
class ErrorRecoveryTest < ApiTestCase
  def test_retry_on_server_error
    call_count = 0
    
    stub_api_request(:get, '/users/123')
      .to_return do |request|
        call_count += 1
        if call_count < 3
          { status: 503 }
        else
          { 
            status: 200,
            body: { id: 123 }.to_json
          }
        end
      end
    
    user = RetryableRequest.execute { TestApi::User.retrieve('123') }
    assert_equal 123, user.id
    assert_equal 3, call_count
  end
  
  def test_circuit_breaker
    # Multiple failures trigger circuit breaker
    5.times do
      stub_api_request(:get, '/users/123').to_return(status: 503)
      
      assert_raises(TestApi::ApiError) do
        TestApi::User.retrieve('123')
      end
    end
    
    # Circuit is now open
    assert_raises(TestApi::ApiConnectionError) do
      TestApi::User.retrieve('123')
    end
  end
end
```

## Mocking and Stubbing

### Stubbing HTTP Requests

```ruby
class StubExamplesTest < ApiTestCase
  def test_stub_with_headers
    stub_api_request(:get, '/users/123')
      .with(headers: { 'Authorization' => 'Bearer test-key' })
      .to_return(
        status: 200,
        body: { id: 123 }.to_json,
        headers: { 'X-Request-Id' => 'abc123' }
      )
    
    user = TestApi::User.retrieve('123')
    assert_equal 123, user.id
  end
  
  def test_stub_with_query_params
    stub_api_request(:get, '/users')
      .with(query: hash_including({ status: 'active' }))
      .to_return(body: { data: [] }.to_json)
    
    TestApi::User.list(status: 'active', page: 1)
    # Test passes if request matches
  end
  
  def test_stub_sequence
    stub_api_request(:get, '/users/123')
      .to_return(status: 503)
      .then.to_return(status: 200, body: { id: 123 }.to_json)
    
    # First call fails
    assert_raises(TestApi::ApiError) do
      TestApi::User.retrieve('123')
    end
    
    # Second call succeeds
    user = TestApi::User.retrieve('123')
    assert_equal 123, user.id
  end
end
```

### Mocking Client Behavior

```ruby
class ClientMockTest < ApiTestCase
  def test_mock_client
    mock_client = Minitest::Mock.new
    mock_response = TestApi::Response.new(
      status: 200,
      body: { id: 123 }.to_json,
      headers: {}
    )
    
    mock_client.expect(:execute_request, mock_response, [
      :get, '/users/123', { params: {}, headers: {} }
    ])
    
    TestApi::Client.stub :active_client, mock_client do
      user = TestApi::User.retrieve('123')
      assert_equal 123, user.id
    end
    
    mock_client.verify
  end
  
  def test_mock_connection
    mock_connection = Minitest::Mock.new
    
    TestApi::Client.stub :default_connection, mock_connection do
      client = TestApi::Client.new
      assert_equal mock_connection, client.connection
    end
  end
end
```

## Testing with VCR

### Basic VCR Usage

```ruby
class VcrTest < ApiTestCase
  def test_real_api_call
    VCR.use_cassette('user_retrieve') do
      user = TestApi::User.retrieve('123')
      assert_equal 'John Doe', user.name
    end
  end
  
  def test_list_with_vcr
    VCR.use_cassette('user_list', record: :new_episodes) do
      users = TestApi::User.list
      assert users.count > 0
    end
  end
end
```

### RSpec with VCR Metadata

```ruby
RSpec.describe TestApi::User, :vcr do
  describe '.retrieve' do
    it 'fetches user from API' do
      # Automatically uses cassette named after test
      user = described_class.retrieve('123')
      expect(user.name).to eq('John Doe')
    end
  end
  
  describe '.list', vcr: { cassette_name: 'custom_user_list' } do
    it 'returns list of users' do
      users = described_class.list
      expect(users).not_to be_empty
    end
  end
end
```

### VCR Configuration for Different Environments

```ruby
VCR.configure do |config|
  config.cassette_library_dir = 'test/fixtures/vcr_cassettes'
  config.hook_into :webmock
  
  # Filter sensitive data
  config.filter_sensitive_data('<API_KEY>') { ENV['API_KEY'] }
  config.filter_sensitive_data('<API_SECRET>') { ENV['API_SECRET'] }
  
  # Custom matchers
  config.default_cassette_options = {
    match_requests_on: [:method, :uri, :body],
    record: ENV['VCR_RECORD_MODE'] || :once,
    allow_playback_repeats: true
  }
  
  # Ignore localhost
  config.ignore_localhost = true
  
  # Allow real requests in CI
  config.allow_http_connections_when_no_cassette = ENV['CI'].nil?
  
  # Re-record cassettes periodically
  config.before_record do |interaction|
    # Remove dynamic headers
    interaction.request.headers.delete('X-Request-Id')
    interaction.response.headers.delete('X-Request-Id')
    
    # Expire cassettes after 7 days
    interaction.response.headers['X-VCR-Recorded-At'] = Time.now.utc.to_s
  end
end
```

## Testing Best Practices

### 1. Test Organization

```ruby
# test/unit/resources/user_test.rb
class UserResourceTest < ApiTestCase
  # Test resource methods
end

# test/unit/client_test.rb
class ClientTest < ApiTestCase
  # Test client behavior
end

# test/integration/user_workflow_test.rb
class UserWorkflowTest < ApiTestCase
  # Test complete workflows
end

# test/performance/api_performance_test.rb
class ApiPerformanceTest < ApiTestCase
  # Test performance characteristics
end
```

### 2. Test Helpers

```ruby
module ApiTestHelpers
  def create_test_user(attributes = {})
    default_attributes = {
      id: rand(1000),
      email: "test#{rand(1000)}@example.com",
      name: 'Test User'
    }
    
    TestApi::User.new(
      default_attributes[:id],
      values: default_attributes.merge(attributes)
    )
  end
  
  def stub_successful_response(method, path, response_body)
    stub_api_request(method, path).to_return(
      status: 200,
      body: response_body.to_json,
      headers: { 'Content-Type' => 'application/json' }
    )
  end
  
  def stub_error_response(method, path, status, error_message = nil)
    body = error_message ? { error: error_message } : {}
    stub_api_request(method, path).to_return(
      status: status,
      body: body.to_json
    )
  end
  
  def assert_api_called(method, path, times: 1)
    assert_requested(method, "#{TestApi.api_base}#{path.sub(/^\//, '')}", times: times)
  end
end

class ApiTestCase < Minitest::Test
  include ApiTestHelpers
end
```

### 3. Testing Custom Configurations

```ruby
class ConfigurationTest < ApiTestCase
  def test_custom_configuration
    original_base = TestApi.api_base
    
    TestApi.configure do |config|
      config.api_base = 'https://custom.example.com/'
    end
    
    assert_equal 'https://custom.example.com/', TestApi.api_base
  ensure
    TestApi.api_base = original_base
  end
  
  def test_environment_specific_config
    ENV['API_ENV'] = 'staging'
    
    TestApi.configure do |config|
      config.api_base = case ENV['API_ENV']
        when 'staging' then 'https://staging.example.com/'
        else 'https://prod.example.com/'
      end
    end
    
    assert_equal 'https://staging.example.com/', TestApi.api_base
  ensure
    ENV.delete('API_ENV')
  end
end
```

### 4. Testing Middleware

```ruby
class MiddlewareTest < ApiTestCase
  def test_custom_middleware
    TestApi::Client.class_eval do
      def self.default_connection
        @default_connection ||= Faraday.new do |conn|
          conn.use TestMiddleware
          conn.adapter :test do |stub|
            stub.get('/test') { [200, {}, 'OK'] }
          end
        end
      end
    end
    
    response = TestApi::Client.active_client.execute_request(:get, '/test')
    assert_equal 'Modified by middleware', response.headers['X-Test-Header']
  end
end

class TestMiddleware < Faraday::Middleware
  def call(env)
    @app.call(env).on_complete do |response_env|
      response_env[:response_headers]['X-Test-Header'] = 'Modified by middleware'
    end
  end
end
```

## Continuous Integration

### GitHub Actions Configuration

```yaml
# .github/workflows/test.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        ruby-version: ['3.0', '3.1', '3.2', '3.3']
    
    steps:
    - uses: actions/checkout@v2
    
    - name: Set up Ruby
      uses: ruby/setup-ruby@v1
      with:
        ruby-version: ${{ matrix.ruby-version }}
        bundler-cache: true
    
    - name: Run tests
      env:
        API_KEY: test-key
        API_SECRET: test-secret
      run: |
        bundle exec rake test
        bundle exec rake test:integration
    
    - name: Upload coverage
      uses: codecov/codecov-action@v2
      with:
        files: ./coverage/coverage.xml
```

### Test Coverage

```ruby
# test/test_helper.rb
require 'simplecov'
SimpleCov.start do
  add_filter '/test/'
  add_filter '/spec/'
  add_group 'Resources', 'lib/api/resources'
  add_group 'Client', 'lib/api/client'
  add_group 'Middleware', 'lib/api/middleware'
end

# Ensure minimum coverage
SimpleCov.minimum_coverage 90
SimpleCov.minimum_coverage_by_file 80
```

### Performance Testing

```ruby
require 'benchmark'

class PerformanceTest < ApiTestCase
  def test_resource_creation_performance
    time = Benchmark.realtime do
      1000.times do
        TestApi::User.new('123', values: { email: 'test@example.com' })
      end
    end
    
    assert time < 1.0, "Resource creation took #{time}s, expected < 1s"
  end
  
  def test_parallel_requests
    stub_api_request(:get, '/users/123')
      .to_return(body: { id: 123 }.to_json)
    
    time = Benchmark.realtime do
      threads = 10.times.map do
        Thread.new { TestApi::User.retrieve('123') }
      end
      threads.each(&:join)
    end
    
    assert time < 2.0, "Parallel requests took #{time}s"
  end
end
```