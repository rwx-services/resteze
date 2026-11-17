# AGENTS.md

Guidance for AI coding agents. There are two audiences, so find yours first:

- **You are building or changing a client gem that uses Resteze.** Read
  [Using Resteze in a client](#using-resteze-in-a-client), then
  [docs/BUILDING_A_CLIENT.md](docs/BUILDING_A_CLIENT.md).
- **You are working on Resteze itself**, in this repository. Read from
  [About](#about) onward.

## Using Resteze in a client

Resteze is a framework for REST API client gems. A client is a module that
does `include Resteze`, plus one small class per resource.

1. Read [docs/BUILDING_A_CLIENT.md](docs/BUILDING_A_CLIENT.md) first. It maps
   what an API looks like to the feature to use, shows a complete client, and
   lists what not to do. The other files in `docs/` are reference.
2. The docs ship inside the gem. In a client project, `bundle info resteze
   --path` prints where it is installed; `docs/` and this file are there.
3. Prefer a declaration to an override. Nested paths are `path_template`,
   extra endpoints are `action`, authentication is `authenticate_with`,
   pacing is `rate_limit_with`. If you are about to override `resource_path`,
   `list` or `retrieve_params`, or to build a URL by hand, stop and check
   the guide's table.
4. Inside the module, use the per-module classes by their short names:
   `class Widget < ApiResource`, `include List`, `rescue WidgetApi::Error`.
   Never rescue `Faraday::` classes or inherit from `Resteze::Object`.
5. Test declarations with `has_property` and `has_action` from
   `resteze/testing/minitest` or `resteze/testing/rspec`, and requests with
   WebMock.

The rest of this file is for work on Resteze itself.

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
- `MyApi::Result` — Hashie::Mash subclass returned by custom actions that declare no `returns:`
- `MyApi::Middleware::RaiseError` — Faraday middleware for HTTP error handling
- `MyApi::List`, `MyApi::Save`, `MyApi::Destroy` — mixins consumers include on specific resources
- `MyApi::Error` and all subclasses — namespaced error hierarchy
- `MyApi::Authenticator` — per-module `Resteze::Authenticator` subclass; `MyApi.authenticator` is the thread-shared instance. `authenticate_with <name or Strategy class>, **options` on the module (or `strategy` inside the class; combinable) adds a `Resteze::Authenticator::Strategy` subclass; built-in schemes call `Strategy.register(:name, self)` (`lib/resteze/authenticator/`), and a gem can register its own. A strategy's `DEFAULTS` name the module settings it expects, which `authenticate_with` declares. `Resteze::Authenticating` is prepended on `Client` to call `apply(request)` before each request and retry once when `refresh?` says so; `connection_options` feed `Client.default_connection`
- `MyApi::RateLimiter` — per-module `Resteze::RateLimiter` subclass; `MyApi.rate_limiter` is the thread-shared instance the client consults (`before_request`, `track`, `retry?`, `retry_after`, `rate_limit`). `strategy :fixed_window | :sliding_window | :token_bucket | :leaky_bucket, **options` picks a built-in algorithm (`lib/resteze/rate_limiter/`); `Resteze::RateLimiting` is prepended outermost on `Client` to drive it and retry

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

### Mixins: List, Save and Destroy

- **`Resteze::List`** adds a class-level `.list(params:)` that issues a GET to `resource_path` and constructs a `ListObject`.
- **`Resteze::Save`** adds `#save` which issues POST (new) or PUT (persisted) based on `persisted?` (presence of `id`).
- **`Resteze::Destroy`** adds `#destroy` and `.destroy(id)`, which issue DELETE to `resource_path` and return a `Result` via the overridable `process_destroy_response`.

All three are opt-in; include them on a resource class when needed.

### Actions: the routing DSL

`Resteze::Actions` (mixed into `ApiResource`) provides a Rails-style `action` DSL. `action :track, method: :post` on a resource generates `Klass.track(**params)`; `on: :member` generates an instance method plus `Klass.name(id, **params)`. Five names are reserved (`retrieve`, `list`, `create`, `update`, `destroy`): they are pre-registered with REST defaults, never generate methods, and can be re-routed by redeclaring them (`action :retrieve, path: "details", id: :param`).

Resolution is lazy. `Klass.actions` rebuilds a frozen hash of `Resteze::Action` value objects on every call by merging, lowest priority first: `Action::BUILT_IN` → the module's `action_defaults` → the module's `action` declarations → ancestor classes' `declared_actions` → the class's own. `refresh`, `list`, `save` and `destroy` consult the registry for their route (`retrieve_resource_path`, `list_resource_path`, `save_resource_path`, `save_params`, `destroy_resource_path`, `destroy_params`) but keep their own bodies. Custom actions return `MyApi::Result` (a `Hashie::Mash`) unless `returns:` names `:self`, `:list` or an `Object` subclass. Declaration-time validation lives in `Resteze::Actions::Validation`. See `docs/ACTIONS.md`.

### Nested resources: `path_template`

`Resteze::PathTemplate` (mixed into `ApiResource`) lets a resource declare `path_template "catalogs/:catalog_name/items"`. `Klass.nested?` is true for such a class and `Klass.path_tokens` lists the token names (the class has no `path_params`; that is the instance's hash of values). `resource_path(id, **path_params)` fills it and `Action#path_for(id, path_params)` passes the values through, so every built-in and custom action nests, `destroy` included (`Item.destroy(id, catalog_name: "shoes")`). Class methods (`list`, `retrieve`, `new`, class forms of actions) take the tokens and an optional `parent:` as keywords via `partition_path_keywords` / `path_context!`; instances hold them outside the properties (`path_params`, `path_parent`, generated readers) and objects built by a call get them through `apply_path_context`. The instance form of a member action treats every keyword as a request param. There is no association layer. See `docs/NESTED_RESOURCES.md`.

### Documentation is tested

`test/docs_test.rb` checks `README.md`, `AGENTS.md` and `docs/*.md` against the gem: every `ruby` example must parse, every file under `resteze/` that an example requires must load, every `Resteze::` constant must exist, and every `include`d mixin must be one Resteze defines. When you add or rename a public name, update the docs in the same change; when an example is not Ruby, fence it as something else (`yaml`, `text`).

### Testing helpers

`lib/resteze/testing/` provides helpers for consumers testing their own gem:
- `Resteze::Testing::Minitest` — `has_property` assertion helper and `assert_config_property`
- `Resteze::Testing::RSpec` — equivalent helpers for RSpec

The gem's own tests use **Minitest** with **WebMock** (net connections disabled globally). The test helper defines `AcmeApi` as a reference implementation of a consuming module.
