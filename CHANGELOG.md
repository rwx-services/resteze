# Changelog

All notable changes to this project will be documented in this file.

## [0.5.0]

### Added

- `action` routing DSL on `ApiResource`: declare custom collection and member actions, re-route `retrieve`, `list`, `create` and `update`, and set API-wide defaults with module-level `action` / `action_defaults`.
- `Result`, a loose Mash returned by custom actions by default; `returns:` selects a resource, a list, or any `Object` subclass instead.
- `retrieve_resource_path`, `save_params` and `id_param` override points.
- `has_action` assertion helper for Minitest and RSpec.
- `Response#success?`, true for any 2xx status. `Response#ok?` is unchanged and means exactly 200, so a `201 Created` answers `success?` but not `ok?`.
- `MyApi::RateLimitError`, raised for a 429, with `#retry_after` read from the `Retry-After` header (delay-seconds or HTTP-date).
- `Error.from_faraday` builds a namespaced error from a Faraday error, keeping its status, headers, body, parsed `json_body` and response; `Error#header` looks a header up case-insensitively.

### Changed

- `Response.parse_body` returns a blank body unparsed instead of raising `JSON::ParserError`, so a `200 OK` with an empty body no longer fails.
- `include Resteze` now defines `MyApi::Result`, so `Result` joins `Object`, `Client`, `Response` and the other reserved constant names inside an API module.
- The `RaiseError` middleware now maps every Faraday error onto the API module's hierarchy: 401/403 to `AuthenticationError`, 429 to `RateLimitError`, 400 to `InvalidRequestError`, other 4xx and all 5xx to `ApiError`, and connection failures, timeouts and SSL errors to `ApiConnectionError`. Previously only 404, 409 and 422 were namespaced and everything else surfaced as a raw Faraday error that `rescue MyApi::Error` could not catch. The Faraday error is kept as `cause`.

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
