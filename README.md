<div style="display: block; text-align: center;">
  <img src="assets/resteze.svg" alt="Resteze API Ointment" width="128" style="margin: auto;">
</div>

[![Continuous Integration](https://github.com/rwx-services/resteze/actions/workflows/ci.yml/badge.svg)](https://github.com/rwx-services/resteze/actions/workflows/ci.yml)
[![Gem Version](https://badge.fury.io/rb/resteze.svg)](https://badge.fury.io/rb/resteze)

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

  # Configure your API client
  configure do |config|
    config.api_base = 'https://api.example.com/'
    config.api_key = 'your-api-key'
    config.logger = Logger.new($stdout)
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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/rwx-services/resteze.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
