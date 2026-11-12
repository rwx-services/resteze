<div style="display: block; text-align: center;">
  <img src="assets/resteze.svg" alt="Resteze API Ointment" width="128" style="margin: auto;">
</div>

[![Continuous Integration](https://github.com/rwx-services/resteze/actions/workflows/ci.yml/badge.svg)](https://github.com/rwx-services/resteze/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/resteze.svg)](https://badge.fury.io/rb/resteze)
[![Coverage Status](https://coveralls.io/repos/github/rwx-services/resteze/badge.svg?branch=main)](https://coveralls.io/github/rwx-services/resteze?branch=main)

---

Resteze is a Ruby library designed to simplify the creation of REST API client gems. It provides a flexible framework for defining API resources, handling requests and responses, managing configuration, and supporting common patterns like listing, saving, and error handling. Built on top of popular Ruby libraries such as Faraday, Hashie, and ActiveSupport, Resteze enables developers to quickly build robust, object-oriented clients for RESTful services, with features for custom resource paths, serialization, and thread-safe client management.

But Resteze isn't just for REST! Its resource-oriented design lets you give any API—SOAP, RPC, GraphQL, or even quirky legacy endpoints—a clean, resourceful feel. You can wrap non-RESTful APIs in familiar objects, organize calls as resource methods, and enjoy the same convenience and clarity, no matter how your backend is structured. Resteze helps you tame any API and make it feel right at home in Ruby.

## Installation

You can install Resteze from RubyGems or use it directly from source.

### Install via RubyGems

Add Resteze to your application's Gemfile:

```ruby
bundle add resteze
```

Then run:

```bash
bundle install
```

Or install it directly with:

```bash
gem install resteze
```

## Usage

### Building an API Client with Resteze

To build an API client using Resteze, define a Ruby module for your API and include the `Resteze` concern. Then, create resource classes under your module that inherit from `ApiResource` and define properties for your API objects.

Here's a simple example:

```ruby
require 'resteze'

module MyCoolApi
  include Resteze

  # Settings your API needs beyond the built-in ones
  class << self
    attr_accessor :api_key
  end

  # Configure your API client (an initializer is the usual place)
  configure do |config|
    config.api_base = 'https://api.example.com/'
    config.api_key  = ENV['MY_COOL_API_KEY']
    config.logger   = Logger.new($stdout)
  end

  # Say how the API authenticates: :api_key, :basic, :bearer or :mtls.
  # The credential is a callable, so it is read on each request.
  class Authenticator
    strategy :bearer, token: -> { MyCoolApi.api_key }
  end

  # Define a resource
  class Widget < ApiResource
    property :id
    property :name
    property :status
  end
end

# Usage example
widget = MyCoolApi::Widget.retrieve(123)
puts widget.name

# List resources
widgets = MyCoolApi::Widget.list
widgets.each do |w|
  puts w.id
end
```

You can define additional resources, customize paths, and add methods as needed. Resteze handles requests, responses, and error management for you, so you can focus on your API's business logic.

### Actions

Endpoints that do not fit the REST pattern are declared with the `action` DSL, and the built-in `retrieve`, `list`, `create` and `update` can be re-routed the same way. See [docs/ACTIONS.md](docs/ACTIONS.md).

```ruby
module MyCoolApi
  class Widget < ApiResource
    action :search,   method: :get                 # Widget.search(q: "x") => GET /widgets/search?q=x
    action :activate, method: :post, on: :member   # widget.activate       => POST /widgets/:id/activate
    action :retrieve, path: "details", id: :param  # Widget.retrieve(id)   => GET /widgets/details?widget_id=...
  end
end
```

### Instrumentation

Resteze fires an `ActiveSupport::Notifications` event for every HTTP request, making it easy to track performance metrics in host applications.

The event name is `request.<api_module_key>`, where the key is derived from your module name (e.g. `MyCoolApi` → `"request.my_cool_api"`).

```ruby
ActiveSupport::Notifications.subscribe("request.my_cool_api") do |event|
  event.duration            # elapsed time in milliseconds
  event.payload[:method]    # :get, :post, :put, etc.
  event.payload[:path]      # "/widgets/123"
  event.payload[:status]    # 200, 404, etc.
  event.payload[:request_id] # value of the Request-Id response header
  event.payload[:api_module] # "MyCoolApi"
  event.payload[:exception]  # [ExceptionClass, message] if the request raised
  event.payload[:rate_limit] # { limit:, remaining:, reset: } when the module's RateLimiter reports one
end
```

A second event, `rate_limit.<key>` prefixed as `rate_limit.wait.<key>`, fires whenever the module's `RateLimiter` makes a request wait, before sending or before a retry. Its `duration` is the time actually spent waiting; its payload carries `seconds` (the wait asked for), `reason` (`:throttle` or `:retry`), `attempt` for a retry, and `on_wait`. Under `on_wait: :raise` the event still fires and carries the raised exception, so refused requests are visible too:

```ruby
ActiveSupport::Notifications.subscribe("rate_limit.wait.my_cool_api") do |event|
  event.duration            # milliseconds actually waited
  event.payload[:seconds]   # 30.0
  event.payload[:reason]    # :throttle or :retry
  event.payload[:attempt]   # 1, 2, … for :retry
  event.payload[:exception] # set when on_wait: :raise refused the request instead
end
```

The event fires on every request — including those that raise errors — so you can feed `event.duration` directly into a histogram for p95 and other percentile calculations. When a request raises an error that carries an HTTP response (a `Faraday::Error` or a `Resteze::Error` built with `http_status:`), `status` and `request_id` are populated from that response, so a 404 or 429 is bucketed just like a 200. Connection failures and timeouts have no status and leave those keys unset. Because `ActiveSupport::Notifications` short-circuits when there are no subscribers, there is no overhead when instrumentation is not in use.

To override the event name key for a module:

```ruby
module MyCoolApi
  include Resteze

  INSTRUMENTATION_KEY = "cool_api"
end
# => subscribes to "request.cool_api"
```

## Documentation

- [API](docs/API.md) — core concepts, resource definition, requests and responses
- [Actions](docs/ACTIONS.md) — the `action` routing DSL for custom and re-routed endpoints
- [Advanced Usage](docs/ADVANCED_USAGE.md) — lists, saves, pagination, batching and caching patterns
- [Configuration](docs/CONFIGURATION.md) — module configuration, connections and middleware
- [Error Handling](docs/ERROR_HANDLING.md) — the namespaced error hierarchy and recovery
- [Testing](docs/TESTING.md) — Minitest and RSpec helpers, WebMock and VCR

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rwx-services/resteze.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
