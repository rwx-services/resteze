# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About

Resteze is a Ruby gem that provides a framework for building REST API client libraries. Consumers `include Resteze` in their own module and get a fully namespaced set of classes (Client, ApiResource, ListObject, Error hierarchy, etc.) that they extend to define resources.

## Commands

```bash
bundle exec rake          # Run tests + RuboCop (default task)
bundle exec rake test     # Run tests only
bundle exec rake rubocop  # Lint only
bundle exec ruby -Ilib:test test/resteze/client_test.rb  # Run a single test file
bundle exec guard         # Watch mode: re-runs tests on file changes
COVERAGE=1 bundle exec rake test  # Run tests with coverage report
```

## Architecture

### The `include Resteze` pattern

When a module does `include Resteze`, the `included` block in `lib/resteze.rb` fires and sets up a full set of namespaced constants inside the consuming module:

- `MyApi::Object` — base Hashie::Trash subclass for all resource objects
- `MyApi::Client` — Faraday-based HTTP client (thread-safe via `Thread.current`)
- `MyApi::ApiResource` — extends Object with `retrieve`, `resource_path`, `refresh`
- `MyApi::ListObject` — Hashie::Array subclass for paginated list responses
- `MyApi::Middleware::RaiseError` — Faraday middleware for HTTP error handling
- `MyApi::List`, `MyApi::Save` — mixins consumers include on specific resources
- `MyApi::Error` and all subclasses — namespaced error hierarchy

This means each consuming gem gets its own isolated class hierarchy; errors from one API won't be caught by rescue clauses for another.

### `ApiModule` — the ancestry resolver

`Resteze::ApiModule` is mixed into every class in the hierarchy. Its `api_module` class method walks the constant name ancestry (`Widget` → `MyApi::Widget` → `MyApi`) to find the module that `include`d Resteze. This is what allows `MyApi::Widget.request(...)` to automatically use `MyApi::Client` rather than needing any explicit wiring.

### Request flow

```
MyApi::Widget.retrieve(id)
  → ApiResource#refresh
  → Request.request(:get, path)
  → MyApi::Client.active_client.execute_request(method, path)
  → Faraday connection (thread-local default_client)
  → Middleware::RaiseError
  → Response.from_faraday_response
  → Object#initialize_from(resp.data)
```

GET/HEAD/DELETE params become query strings; all other methods send a JSON body.

### Object / property system

`Resteze::Object` extends `Hashie::Trash`, which provides typed `property` declarations with optional transforms, defaults, and translations (key remapping). Unknown keys that don't match a declared property are stored in `@property_bag` rather than raising, allowing forward compatibility with API changes.

`object_key` (default: `nil`) lets a resource unwrap a top-level envelope key from API responses. `list_key` (default: `:data`) tells `ListObject` which key holds the array of items.

### Mixins: List and Save

- **`Resteze::List`** adds a class-level `.list(params:)` that issues a GET to `resource_path` and constructs a `ListObject`.
- **`Resteze::Save`** adds `#save` which issues POST (new) or PUT (persisted) based on `persisted?` (presence of `id`).

Both are opt-in; include them on a resource class when needed.

### Testing helpers

`lib/resteze/testing/` provides helpers for consumers testing their own gem:
- `Resteze::Testing::Minitest` — `has_property` assertion helper and `assert_config_property`
- `Resteze::Testing::RSpec` — equivalent helpers for RSpec

The gem's own tests use **Minitest** with **WebMock** (net connections disabled globally). The test helper defines `AcmeApi` as a reference implementation of a consuming module.
