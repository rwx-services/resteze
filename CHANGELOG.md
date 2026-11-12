# Changelog

All notable changes to this project will be documented in this file.

## [0.5.0]

### Added

- `action` routing DSL on `ApiResource`: declare custom collection and member actions, re-route `retrieve`, `list`, `create` and `update`, and set API-wide defaults with module-level `action` / `action_defaults`.
- `Result`, a loose Mash returned by custom actions by default; `returns:` selects a resource, a list, or any `Object` subclass instead.
- `retrieve_resource_path`, `save_params` and `id_param` override points.
- `has_action` assertion helper for Minitest and RSpec.

### Changed

- `Response.parse_body` returns a blank body unparsed instead of raising `JSON::ParserError`, so a `200 OK` with an empty body no longer fails.
- `include Resteze` now defines `MyApi::Result`, so `Result` joins `Object`, `Client`, `Response` and the other reserved constant names inside an API module.

### Fixed

- `assert_config_property` (Minitest and RSpec) now assigns the given value before asserting it reads back, then restores the original. It previously only compared the current value.

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
