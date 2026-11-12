# Changelog

All notable changes to this project will be documented in this file.

## [0.5.0]

### Added

- `action` routing DSL on `ApiResource`: declare custom collection and member actions, re-route `retrieve`, `list`, `create` and `update`, and set API-wide defaults with module-level `action` / `action_defaults`.
- `Result`, a loose Mash returned by custom actions by default; `returns:` selects a resource, a list, or any `Object` subclass instead.
- `retrieve_resource_path`, `save_params` and `id_param` override points.
- `has_action` assertion helper for Minitest and RSpec.
- `MyApi::Authenticator`, a per-module subclass of `Resteze::Authenticator` through which a client describes how its API authenticates, with `authenticate_with` (and `rate_limit_with`) module macros so choosing a scheme is one line on the module. The client calls one thread-shared instance (`MyApi.authenticator`) at three points: `connection_options` when the Faraday connection is built, `apply(request)` before every request, and `refresh?(error, attempt)` after a 401 or 403 to send the request once more with a renewed credential. A scheme is a `Resteze::Authenticator::Strategy` subclass; its `DEFAULTS` name the module settings it expects, which `authenticate_with` declares, so an initializer fills them through `configure`. A setting still `nil` at request time raises an `ArgumentError` naming it; `missing_settings` lists them for a boot-time check. `Client#execute_request` gains `query:`, parameters that always go in the query string whatever the method.
- `:api_key` authentication scheme: the module's `api_key` in a header (default `X-Api-Key`) or, with `query:`, in the query string on every request.
- `:basic` authentication scheme: HTTP Basic from the module's `username` and `password`.
- `:bearer` authentication scheme: `Authorization: Bearer <api_key>`, with `scheme:` for another prefix and `token:` for another setting or a callable.
- `:mtls` authentication scheme: a client certificate on the TLS connection from the module's `client_cert` and `client_key` (PEM or path), with `client_key_passphrase`, `ca_file:` and `verify:`.
- `Response#success?`, true for any 2xx status. `Response#ok?` is unchanged and means exactly 200, so a `201 Created` answers `success?` but not `ok?`.
- `MyApi::RateLimitError`, raised for a 429, with `#retry_after` read from the `Retry-After` header (delay-seconds or HTTP-date).
- `Error.from_faraday` builds a namespaced error from a Faraday error, keeping its status, headers, body, parsed `json_body` and response; `Error#header` looks a header up case-insensitively.
- `Response.body_error` hook for APIs that report failures inside a 2xx body. Override it on `MyApi::Response` to return an error to raise; `Error.from_response` builds one from the parsed response.
- `MyApi::RateLimiter`, a per-module subclass of `Resteze::RateLimiter` through which a client describes and responds to its API's rate limiting. The client calls one thread-shared instance (`MyApi.rate_limiter`) at fixed points: `before_request`, `track` after every response or error, `retry?` and `retry_after` after a 429, and `rate_limit` when `Response#rate_limit` or `Error#rate_limit` is read. Every method is a no-op by default; Resteze assumes nothing about the mechanics. State lives in a mutex-guarded hash (`state`, `update_state`, `synchronize`) so subclasses need not manage threads.
- Four built-in strategies, chosen with `strategy` in the module's `RateLimiter`: `:fixed_window` (with optional `headers: true` to follow the API's `X-RateLimit-*` headers, as Braze and JD Power report), `:sliding_window`, `:token_bucket` and `:leaky_bucket`. A strategy makes `before_request` wait until the request fits and `rate_limit` return a `Resteze::RateLimit` of its current view. `on_wait: :raise` raises `RateLimitError` with the wait in `retry_after` instead of sleeping, for callers such as background jobs that reschedule themselves, and applies to retry waits too. `max_wait:` (default one hour) clamps every wait, so a bad `Retry-After` or reset header cannot park a thread indefinitely or crash on a non-finite sleep. Custom algorithms subclass `Resteze::RateLimiter::Strategy`.
- `RateLimitError#retry_after` reads the HTTP `Retry-After` header (delay-seconds or HTTP-date); `Resteze::RateLimit.from_headers` is a helper for the three-header shape.
- A `rate_limit.wait.<key>` notification fires whenever the `RateLimiter` makes a request wait, before sending or before a retry, with the wait's `seconds`, `reason`, `attempt` and `on_wait` in the payload and the time actually waited as its duration; under `on_wait: :raise` it carries the exception instead. The `request.<key>` payload gains `rate_limit`, the limiter's view of the quota, when it reports one.

### Changed

- `Response.parse_body` returns a blank body unparsed instead of raising `JSON::ParserError`, so a `200 OK` with an empty body no longer fails.
- `include Resteze` now defines `MyApi::Result`, so `Result` joins `Object`, `Client`, `Response` and the other reserved constant names inside an API module.
- The `RaiseError` middleware now maps every Faraday error onto the API module's hierarchy: 401/403 to `AuthenticationError`, 429 to `RateLimitError`, 400 to `InvalidRequestError`, other 4xx and all 5xx to `ApiError`, and connection failures, timeouts and SSL errors to `ApiConnectionError`. Previously only 404, 409 and 422 were namespaced and everything else surfaced as a raw Faraday error that `rescue MyApi::Error` could not catch. The Faraday error is kept as `cause`.
- **Breaking:** `MyApi::ResourceNotFound`, `MyApi::ConflictError` and `MyApi::UnprocessableEntityError` are now subclasses of `MyApi::Error` like every other error, so `rescue MyApi::Error` catches a 404, 409 or 422. They no longer descend from the Faraday classes; a `rescue Faraday::ResourceNotFound` must become `rescue MyApi::ResourceNotFound`. Their Faraday-style readers (`response_status`, `response_headers`, `response_body`, `response`) still work, and are now available on every `MyApi::Error`.

### Fixed

- `assert_config_property` (Minitest and RSpec) now assigns the given value before asserting it reads back, then restores the original. It previously only compared the current value.
- The `request.<key>` instrumentation payload now includes `status` and `request_id` when the request raises an error that carries an HTTP response. Previously both were missing for every 4xx and 5xx.
- `MyApi::ResourceNotFound`, `MyApi::UnprocessableEntityError` and `MyApi::ConflictError` now keep the Faraday response (`e.response`, `e.response_status`, `e.response_body`). The middleware previously dropped it when re-raising under the namespaced class.
- `MyApi::ApiError`, `ApiConnectionError`, `AuthenticationError` and `InvalidRequestError` are now real subclasses of `MyApi::Error`, defined on the module. `include Resteze` meant to create them but its `const_defined?` guard found the `Resteze::` originals through the included module and skipped every one, so `MyApi::ApiError` was literally `Resteze::ApiError`, shared by every API and not caught by `rescue MyApi::Error`.

## [0.3.1]

### Added

- Minitest and RSpec testing helpers for resources and configuration.

## [0.3.0]

### Added

- Initial implementation of Resteze, a framework for building REST API client gems.
- Support for defining API resources, requests, and responses.
- Configuration management for API clients.
- Integration with Faraday, Hashie, and ActiveSupport.
- Middleware for error handling and request transformation.
- Serialization and deserialization of API responses.
- Thread-safe client management.
- Flexible resource paths and property mapping.

## [0.1.0] - 2025-08-12

### Added

- First public release.
- Documentation and usage examples.
- CI workflow for RuboCop and tests across Ruby 3.2–3.4.4.
- Code coverage reporting integration.
