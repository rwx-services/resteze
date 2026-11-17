# Building a Client

This is the task-oriented guide: you have an API, and you want a client gem for
it. The other files in `docs/` are reference, organized by feature. Start here,
and follow the links when you need the detail.

It is written for people and for AI coding agents alike. If you are an agent,
read [What not to do](#what-not-to-do) before you write code.

## Table of Contents

- [Before you write code](#before-you-write-code)
- [What the API looks like, and what to use](#what-the-api-looks-like-and-what-to-use)
- [A complete client](#a-complete-client)
- [What not to do](#what-not-to-do)
- [Testing the client](#testing-the-client)
- [Where to read more](#where-to-read-more)

## Before you write code

Answer these about the API. Each answer picks a feature in the next section.

1. **How are paths shaped?** Is the id in the path (`/widgets/42`), or are
   endpoints named by verb (`/widgets/details?widget_id=42`)?
2. **Does any resource live under another?** For example
   `/catalogs/shoes/items`.
3. **Which operations exist beyond read, list, create, update and delete?**
4. **What does a list response look like?** Which key holds the items, and
   what else comes back beside them?
5. **Are single records wrapped in an envelope**, such as `{ "widget": {...} }`?
6. **How does it authenticate?** A key in a header or query param, HTTP Basic,
   a bearer token, a client certificate, or something else.
7. **Which statuses mean failure, and can a 2xx carry an error in its body?**
8. **How does it rate-limit, and should the client retry a 429?**
9. **What should callers rescue?** `rescue MyApi::Error` is the catch-all.
   Name the specific classes they will want: `RateLimitError`,
   `AuthenticationError`, `ResourceNotFound`.

## What the API looks like, and what to use

| The API... | Use | Read |
|---|---|---|
| puts the id in the path and uses GET, POST and PUT conventionally | Nothing. Paths come from the class name. | [API.md](API.md) |
| names a resource differently from its class | `def self.resource_slug` on the resource, or `default_resource_slug(klass)` on the module | [API.md](API.md) |
| has a path prefix or a version segment | `default_service_path(klass)` and `default_api_version(klass)` on the module | [API.md](API.md) |
| has a list endpoint | `include List` on the resource | [ADVANCED_USAGE.md](ADVANCED_USAGE.md) |
| creates and updates records | `include Save` on the resource | [ADVANCED_USAGE.md](ADVANCED_USAGE.md) |
| deletes records | `include Destroy` on the resource | [ADVANCED_USAGE.md](ADVANCED_USAGE.md) |
| returns list items under a key other than `data` | `def self.list_key` on the resource, or `default_list_key(klass)` on the module | [API.md](API.md) |
| wraps a single record in an envelope | `def self.object_key` on the resource, or `default_object_key(klass)` on the module | [API.md](API.md) |
| has an operation beyond the standard five | `action :name, method: :post` (add `on: :member` when it acts on one record) | [ACTIONS.md](ACTIONS.md) |
| addresses the standard operations by verb, or sends the id as a param | Re-route them: `action :retrieve, path: "details", id: :param`. Set it once for every resource with module-level `action` and `action_defaults` | [ACTIONS.md](ACTIONS.md) |
| nests a resource under a parent | `path_template "catalogs/:catalog_name/items"` | [NESTED_RESOURCES.md](NESTED_RESOURCES.md) |
| authenticates with a key, Basic, a bearer token or a client certificate | `authenticate_with :api_key`, `:basic`, `:bearer` or `:mtls` on the module | [CONFIGURATION.md](CONFIGURATION.md#authentication) |
| authenticates some other way | A `Resteze::Authenticator::Strategy` subclass, passed to `authenticate_with` | [CONFIGURATION.md](CONFIGURATION.md#writing-a-scheme) |
| reports failures inside a 2xx body | Override `Response.body_error` in the module | [ERROR_HANDLING.md](ERROR_HANDLING.md) |
| rate-limits | `rate_limit_with :fixed_window`, `:sliding_window`, `:token_bucket` or `:leaky_bucket` on the module | [CONFIGURATION.md](CONFIGURATION.md#rate-limits) |
| should be retried after a 429 | Override `retry?` in the module's `RateLimiter` | [CONFIGURATION.md](CONFIGURATION.md#retrying-after-a-429) |
| needs a setting Resteze does not ship | `attr_accessor` on the module's singleton class | [CONFIGURATION.md](CONFIGURATION.md#custom-configuration-properties) |

If nothing in the table fits one endpoint, a resource is an ordinary class and
`request(:post, path, params: {...})` is available on it. Use that for the
one-off, not as the default.

## A complete client

Every feature in this example is optional except `include Resteze`.

```ruby
require "resteze"

module WidgetApi
  include Resteze

  # Authentication. :bearer reads the token from WidgetApi.api_key, a setting
  # this line declares.
  authenticate_with :bearer

  # Pacing: at most 100 requests per 60 seconds, per process.
  rate_limit_with :fixed_window, limit: 100, window: 60

  # This API returns list items under the resource's own name.
  def self.default_list_key(klass)
    klass.resource_slug.to_sym
  end

  # This API reports some failures inside a 200.
  class Response
    def self.body_error(response)
      data = response.data
      return unless data.is_a?(Hash) && data[:errors].present?

      ApiError.from_response(response, data[:message])
    end
  end

  # A plain REST resource: nothing to route.
  #   GET /widgets, GET /widgets/42, POST /widgets, PUT /widgets/42,
  #   DELETE /widgets/42
  class Widget < ApiResource
    include List
    include Save
    include Destroy

    property :id
    property :name
    property :status
    property :created_at, transform_with: ->(value) { Time.parse(value) }

    # POST /widgets/42/archive
    action :archive, method: :post, on: :member
    # GET /widgets/search?q=...  returning a list of widgets
    action :search, method: :get, returns: :list
  end

  # A resource whose standard operations are addressed by verb.
  #   GET /campaigns/details?campaign_id=42
  class Campaign < ApiResource
    property :id
    property :name

    action :retrieve, path: "details", id: :param
  end

  # A nested resource.
  #   GET /catalogs/shoes/items, GET /catalogs/shoes/items/sku1
  class Item < ApiResource
    include List
    include Save

    property :id
    property :price

    path_template "catalogs/:catalog_name/items"
  end

  class Catalog < ApiResource
    property :name

    def items(params: {})
      Item.list(catalog_name: name, parent: self, params:)
    end
  end
end

WidgetApi.configure do |config|
  config.api_base     = "https://api.widgets.example/"
  config.api_key      = ENV.fetch("WIDGET_API_KEY", nil)
  config.open_timeout = 5
  config.read_timeout = 15
end
```

Calling it:

```ruby
widget = WidgetApi::Widget.retrieve(42)
widget.name = "Large sprocket"
widget.save
widget.archive
widget.destroy

WidgetApi::Widget.list(params: { page: 2 })
WidgetApi::Widget.search(q: "sprocket")

WidgetApi::Campaign.retrieve(42)

WidgetApi::Item.list(catalog_name: "shoes")
WidgetApi::Item.retrieve("sku1", catalog_name: "shoes")

begin
  WidgetApi::Widget.retrieve(999)
rescue WidgetApi::ResourceNotFound
  nil
rescue WidgetApi::RateLimitError => e
  sleep(e.retry_after || 1)
  retry
rescue WidgetApi::Error => e
  warn "#{e.http_status}: #{e.message}"
end
```

`include Resteze` creates `WidgetApi::ApiResource`, `WidgetApi::Client`,
`WidgetApi::Response`, `WidgetApi::Error` and the rest, so inside the module
you refer to them by their short names.

## What not to do

Each of these works against something Resteze already does.

| Don't | Do instead | Why |
|---|---|---|
| Override `resource_path`, `list`, `list_resource_path` or `retrieve_params` to reach a nested path | `path_template` | Overrides bypass the action registry, so re-routed and custom actions stop nesting. |
| Hand-write a class method that calls `request` for each extra endpoint | `action` | The DSL validates the declaration, generates both class and instance forms, and is visible to `has_action` in tests. |
| Build URLs with string interpolation | Let `resource_path` and `action` build them | Ids and path values are percent-encoded for you; interpolation is not. |
| `rescue Faraday::Error` or any `Faraday::` class | `rescue WidgetApi::Error` and its subclasses | Every failure is mapped onto the module's own hierarchy. The Faraday error is `e.cause`. |
| `rescue Resteze::Error` to catch one API's errors | `rescue WidgetApi::Error` | Each module has its own hierarchy so that two clients in one process stay apart. |
| Inherit from `Resteze::Object` or look for a `Resteze::ApiResource` class | `class Widget < ApiResource` inside the module | The per-module classes are what know which client and configuration to use. |
| Set headers or credentials in each resource | `authenticate_with` on the module | It is applied to every request, retried once on a 401 when the scheme can refresh, and masked in the debug log. |
| Sleep and retry on a 429 inside resources | `rate_limit_with` and `retry?` on the module's `RateLimiter` | The limiter is shared across threads and consulted before each request. |
| Put a parent's id into `params:` for a nested resource | Pass it as a path keyword: `Item.list(catalog_name: "shoes")` | Path values never reach the query string or body. |
| Store per-request state on a resource class | Keep it on instances | Classes are shared by every thread. |
| Declare every field the API returns | Declare the ones you use | Undeclared keys are kept in the property bag, so a new field never breaks an old client. |

## Testing the client

Use WebMock for requests and the helpers in `lib/resteze/testing/` for
declarations. `has_property` and `has_action` assert what a resource declares
without making a request:

```ruby
require "resteze/testing/minitest"

class WidgetTest < Minitest::Spec
  include Resteze::Testing::Minitest::Object

  subject { WidgetApi::Widget }

  it "declares its properties and routes" do
    has_property :id
    has_property :created_at, transformed: true
    has_action :archive, method: :post, on: :member, path: "/widgets/ID/archive"
    has_action :retrieve, path: "/widgets/ID"
  end
end
```

`require "resteze/testing/rspec"` provides the same helpers for RSpec. See
[TESTING.md](TESTING.md).

## Where to read more

| File | Covers |
|---|---|
| [API.md](API.md) | Core concepts, resources, properties, requests and responses |
| [ACTIONS.md](ACTIONS.md) | The `action` DSL: custom actions, re-routing, defaults, return values |
| [NESTED_RESOURCES.md](NESTED_RESOURCES.md) | `path_template`, path values, the `parent:` reference |
| [CONFIGURATION.md](CONFIGURATION.md) | Settings, authentication, connections, logging, rate limits |
| [ERROR_HANDLING.md](ERROR_HANDLING.md) | The error hierarchy, what an error carries, `body_error` |
| [ADVANCED_USAGE.md](ADVANCED_USAGE.md) | Lists, saves, pagination and batching patterns |
| [TESTING.md](TESTING.md) | Minitest and RSpec helpers, WebMock and VCR |
