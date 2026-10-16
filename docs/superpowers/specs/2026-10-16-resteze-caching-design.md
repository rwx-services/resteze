# Resteze Response Caching — Design

- **Date:** 2026-10-16
- **Status:** Approved design, pending implementation plan
- **Target version:** 0.5.0

## Context and Intent

Resteze consumers repeatedly fetch the same resources — within a single web request,
across background jobs, and against upstream APIs that are slow, expensive, or
quota-limited. Today each consumer hand-rolls caching; `docs/ADVANCED_USAGE.md`
ships two different ad-hoc recipes (a `CachedClient` subclass and a bespoke
`RedisCache` wrapper), neither of which composes with the rest of the framework.

This design adds first-class GET response caching to resteze.

The driving requirement: **TTL is resolved per-resource at cache-write time**, with
fallback to a module-level default. That is why this is not simply
`faraday-http-cache` in the connection stack — TTL is scoped to the *resource class*,
which Faraday middleware cannot see.

### Success criteria

1. A resource declares its own TTL in one line; omitting the declaration inherits a
   module-level default.
2. Caching is inert unless a consumer explicitly configures a store AND explicitly
   opts a resource in.
3. The store is pluggable: memory, Redis, Memcached, `Rails.cache`, or a custom
   `ActiveSupport::Cache::Store`.
4. Multi-tenant consumers cannot accidentally serve one tenant's data to another.
5. Zero new runtime dependencies.

### Non-goals

- **HTTP cache semantics.** `Cache-Control`, `ETag`, `Last-Modified`, and 304
  revalidation are out of scope. TTL is declared by the consumer, not negotiated with
  the server. (A future `revalidate: true` option could layer on; nothing here
  precludes it.)
- **Caching non-GET requests.** POST/PUT/PATCH/DELETE responses are never stored and
  never served from cache. This is a hard rule, not a configurable one.
- **Caching errors.** Not a feature to build — it falls out for free. See §7.
- **Transport concerns.** Retries, circuit breakers, rate limiting, and connection
  pooling are not resource-aware and belong in Faraday middleware, which consumers
  already compose via `Client.default_connection`.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Ship in `resteze`, not a separate `resteze-caching` gem | Zero new dependencies (`ActiveSupport::Cache` is already present via `activesupport`); a separate gem would still require a core extension point and release; the intercept reads `Request`/`api_module` internals, which is fragile across a gem boundary at pre-1.0 |
| 2 | Intercept at the Request layer | `self` IS the resource class there, so `cache_ttl` resolves with no context plumbing |
| 3 | GET only | Writes never read from, nor write to, the cache |
| 4 | A write evicts the record's cached GET | Kills the most surprising staleness (re-reading a record you just wrote); lists lag to TTL |
| 5 | No generation counter | Would put an extra cache read on every lookup to serve a rare need |
| 6 | `cache_for` macro for TTL | Readable and self-documenting; the gem's first class-level DSL, kept thin |
| 7 | `include Cacheable` opts in; `cache_for` tunes | Matches the `List`/`Save` idiom; caching stays visible in the class body |
| 8 | Store primitives, rebuild `Response` | Survives Marshal/JSON/Memcached; immune to `Faraday::Utils::Headers` version skew |
| 9 | Explicit `cache_store`; omitted means disabled | Caching never switches on by accident |
| 10 | Auto key + overridable `cache_scope` | Safe default, one-method escape hatch for tenancy |
| 11 | `uncached` / `refresh_cache` blocks + explicit expiry | Thread-local and block-scoped, so no method signatures change |
| 12 | Bulk expiry uses `delete_matched`, wraps the failure | Honest about the one place the store abstraction leaks |
| 13 | Fold cache status into the existing `request.*` event | One event stream; see §8 for the behavior change this implies |

### The scope rule

To keep resteze from becoming a kitchen sink, this design adopts a principle for
future cross-cutting features:

> **Resource-aware concerns belong in resteze. Pure transport concerns belong in
> Faraday middleware.**

Caching qualifies because TTL is scoped to the resource class. Retries and circuit
breakers do not, and consumers already compose those by overriding
`Client.default_connection`.

## 1. Configuration

Two new accessors on the consuming module, alongside `api_base` and `open_timeout`.

`configure` is `yield self` (`lib/resteze.rb:10-12`) — an ordinary class method, not a
definition-time DSL. It can be called from anywhere, at any time, any number of
times. **Configuration therefore belongs in the host application, separate from the
module definition**, and a Rails initializer is the expected home:

```ruby
# lib/my_api.rb — definition, ships with the client gem
module MyApi
  include Resteze
end
```

```ruby
# config/initializers/my_api.rb — configuration, lives in the host app
MyApi.configure do |config|
  config.api_base    = ENV.fetch("MY_API_URL")
  config.cache_store = Rails.cache   # omit → caching disabled entirely
  config.default_ttl = 60            # Integer seconds or ActiveSupport::Duration
end
```

`Rails.cache` is available here: the `:initialize_cache` bootstrap runs before
`:load_config_initializers`. (Unrelated caveat worth documenting: if the consuming
module were defined under `app/` rather than in a gem, referencing it from an
initializer would autoload during initialization, which Zeitwerk objects to. For a
gem required via the Gemfile, this does not arise.)

Non-Rails consumers call `MyApi.configure` from wherever they do boot-time setup; and
any consumer may re-call it later to change configuration at runtime.

### What `cache_store` accepts

Either a store, or something that returns one:

```ruby
config.cache_store = Rails.cache                  # eager — resolved once
config.cache_store = -> { Rails.cache }           # lazy — current Rails.cache per request
config.cache_store = -> { Tenant.current.cache }  # lazy — per-tenant routing
```

```ruby
def store
  configured = api_module.cache_store
  configured.respond_to?(:call) ? configured.call : configured
end
```

The lazy form exists because the eager form captures the *object*, not the reference.
A test suite that assigns `Rails.cache = ActiveSupport::Cache::MemoryStore.new` in
setup, or an environment that swaps the cache after boot, would otherwise keep writing
to a stale store with no visible symptom.

When the resolved store is `nil`, `include Cacheable` is a silent no-op: every request
goes to the wire and nothing is ever written. This is deliberate — caching requires
asking twice, once in config and once per resource.

### Configuration is never snapshotted

Because configuration may land after classes are loaded and after requests have been
served, **nothing in the caching layer may memoize it**. The store is resolved per
request, not built once per resource class and held. A `Caching::Store` wrapper
memoized at class-definition time would silently ignore every later `configure` call —
including the initializer, which by definition runs after the gem's classes are loaded.

This extends the no-memoization rule in §10 from TTLs and keys to the store itself.

Two new module-level hooks follow the existing `default_*(klass)` idiom
(`default_list_key`, `default_resource_slug`):

```ruby
module Resteze
  module ClassMethods
    def default_cache_ttl(_klass)
      respond_to?(:default_ttl) ? default_ttl : nil
    end

    def default_cache_scope(_klass)
      nil
    end
  end
end
```

The `respond_to?` guard exists because `api_module` can resolve to `Resteze` itself
(see `ApiModule#api_module`), which never ran the `included do` block that defines
the accessors.

Overriding `default_cache_ttl` lets a module express TTL policy across many resources
without annotating each one.

## 2. TTL resolution

First non-nil wins:

| Call | Chain |
|---|---|
| `Widget.retrieve(42)` | `Widget.cache_ttl` → `MyApi.default_cache_ttl(Widget)` → `MyApi.default_ttl` |
| `Widget.list` | `Widget.list_cache_ttl` → `Widget.cache_ttl` → `MyApi.default_cache_ttl(Widget)` → `MyApi.default_ttl` |

A resolved TTL of `nil` or `0` means "do not cache this call" — a per-resource off
switch that works even when a module default is set.

```ruby
module MyApi
  class Currency < ApiResource
    include Cacheable                        # inherits MyApi.default_ttl
  end

  class Widget < ApiResource
    include List
    include Cacheable
    cache_for 5.minutes, list: 30.seconds    # records vs collections
  end

  class Receipt < ApiResource
    include Cacheable
    cache_for nil                            # explicitly never cached
  end

  class Order < ApiResource                  # no mixin, no caching
  end
end
```

## 3. Layout

```
lib/resteze/caching.rb            # shared helpers, thread-local state, namespace
lib/resteze/caching/cacheable.rb  # the mixin: cache_for, cache_scope, request override
lib/resteze/caching/key.rb        # key composition
lib/resteze/caching/entry.rb      # {status, headers, body} ⇄ Response
lib/resteze/caching/store.rb      # AS::Cache wrapper; null-safe; wraps NotImplementedError
```

Changes to `lib/resteze.rb`:

- `require` the five files above
- add `:cache_store, :default_ttl` to the `attr_accessor` list in `included do`
- `const_set(:Cacheable, Module.new)` alongside `List` and `Save`, following the same
  `.module_eval` idiom those use (`lib/resteze.rb:108-116`):

  ```ruby
  const_set(:Cacheable, Module.new).module_eval do
    extend ActiveSupport::Concern
    include Resteze::Caching::Cacheable
  end
  ```
- add `uncached`, `refresh_cache`, `clear_cache`, `default_cache_ttl`, and
  `default_cache_scope` to `ClassMethods`

New error class in `lib/resteze/errors.rb`:

```ruby
class CacheError < Error; end
```

It is namespaced into consumers automatically by the existing `Error.subclasses` loop
in `lib/resteze.rb`, yielding `MyApi::CacheError`.

### Why not prepend globally

`Instrumentation` is prepended into `Client`, so the parallel move would be
`Resteze::Request::ClassMethods.prepend(Resteze::Caching)`. This design instead
defines `request` in `Cacheable::ClassMethods` and calls `super`.

Ruby's method lookup makes this reliable: `Request::ClassMethods` is extended onto the
generated `MyApi::ApiResource`, so it sits in the *superclass's* singleton ancestry,
while `include Cacheable` in `Widget`'s body extends `Cacheable::ClassMethods` onto
`Widget` itself — strictly closer. `super` reaches the original.

The benefit is that non-cacheable resources execute literally no caching code, rather
than a global prepend that must test `cacheable?` on every request in the system.

## 4. Key composition

```
my_api/widget/42:a3f9c1d4e5b6...          ← record
my_api/widget/collection:7b2e0f91ac34...  ← list
my_api/widget/42/export:1c8d...           ← custom endpoint under a record
```

Structure: `<namespace>/<resource_slug>/<record_segment>:<digest>`

- **namespace** — `api_module.name.underscore.tr("/", "_")` (the same transform
  `INSTRUMENTATION_KEY` uses, computed independently so the two can diverge)
- **resource_slug** — `klass.resource_slug`
- **record_segment** — `path.delete_prefix(klass.resource_path).delete_prefix("/")`,
  or `"collection"` when that is blank
- **digest** — first 32 chars of `Digest::SHA256.hexdigest` over
  `[api_base, cache_scope, method, path, normalized_params]`

The record id lives in the **prefix**, not the digest. That is what makes the targeted
eviction in §6 possible.

Two implementation details that are easy to get wrong:

1. **Params must be normalized through `util.objects_to_ids` before digesting.** That
   normalization currently happens in `Client#execute_request` (`client.rb:76`), which
   is *below* this intercept. Without it, `Widget.retrieve(widget)` and
   `Widget.retrieve(widget.id)` would produce different keys for an identical request.
2. **Params are deep-sorted before digesting**, so hash insertion order cannot shard
   the cache into redundant entries.

`api_base` is in the digest so staging and production entries never collide in a
shared store.

### Tenancy

`cache_scope` defaults to `nil` and is overridden per resource (or module-wide via
`default_cache_scope`):

```ruby
module MyApi
  class Widget < ApiResource
    include Cacheable
    cache_for 5.minutes

    def self.cache_scope
      MyApi.current_tenant
    end
  end
end
```

This matters: `docs/CONFIGURATION.md` documents multi-tenant clients that swap
`api_url` and inject `X-Tenant-ID` per `Thread.current`. Without a scope component,
tenant A's widget would be served to tenant B — same path, same params, different
credentials. Request headers are deliberately *not* folded into the key automatically:
they are computed in `Client`, below this layer, and volatile values (nonces, request
ids, timestamps) would shatter the cache into single-use entries.

The default of `nil` is safe for the common single-tenant case and keeps it
friction-free. Multi-tenant consumers override one method. This must be prominent in
the documentation.

## 5. Cache entry format

Stored value is a plain hash of primitives:

```ruby
{ status:  200,
  headers: { "content-type" => "application/json", "link" => "<...>; rel=next" },
  body:    "{\"id\":42,...}" }
```

Headers are flattened to a plain `Hash` of `String => String` via
`faraday_response.headers.to_h`. Nothing Hashie-backed, Faraday-backed, or
resteze-version-specific is serialized, so entries survive Marshal, JSON coders,
Memcached, and gem upgrades alike.

On read, `Resteze::Response.from_cache` rebuilds a `Response` through the same path as
`from_faraday_response`, so the consumer's own `parse_body` override stays
authoritative and `http_headers` survives intact (Link-header pagination, rate-limit
headers, ETags).

This costs a JSON re-parse per hit. Accepted: correctness and portability over
microseconds.

`Response` gains `#cached?`, set true only on entries rebuilt from cache.

Note that `request_id` is replayed from the original response. A cached hit therefore
reports the request id of the request that populated it. Documented, not corrected —
rewriting it would be more confusing than preserving it.

## 6. Lifecycle

### GET on a cacheable resource

1. Return `super` immediately if the store is unconfigured, the resolved TTL is
   `nil`/`0`, or `uncached` is active.
2. Unless `refresh_cache` is active, read the key. On a hit, rebuild and return the
   `Response`.
3. On a miss, call `super`, write the entry with the resolved TTL, return the response.

### Non-GET on a cacheable resource

Never read, never written — straight to the wire. On success, evict:

1. Exact-key delete of the param-less record key.
2. Best-effort `delete_matched` on `<ns>/<slug>/<id>:*` and `<ns>/<slug>/<id>/*`, to
   catch param variants such as `retrieve(id: 42, expand: "owner")`.

**Known compromise.** On Redis, Memory, and File stores, step 2 evicts every variant
of that record. On Memcached, `delete_matched` raises `NotImplementedError`; the
caching layer rescues and swallows it, leaving the param-less key evicted (step 1
succeeded) and variants lagging to TTL.

This degrades quietly, unlike the explicit bulk methods in §9 which raise. The
asymmetry is intentional: step 2 is implicit cleanup the caller did not request, so
failing it loudly would turn every `save` into an exception on Memcached. An explicit
`expire_cache_all` call deserves to fail loudly because the caller is relying on it.

Cached list responses are not evicted by a write; they lag by at most one
`list_cache_ttl`. This is the accepted trade for keeping the read path free of a
generation-counter round trip.

### Bypass

```ruby
MyApi.uncached      { ... }   # read: skip, write: skip
MyApi.refresh_cache { ... }   # read: skip, write: yes — warms the cache
```

Both are thread-locals saved and restored around the block, mirroring
`Client#request` (`client.rb:61-71`), so they nest safely and are exception-safe. When
both are active, `uncached` wins — the more conservative behavior.

Being block-scoped rather than keyword arguments means no method signatures change and
they compose with `retrieve`, `list`, and any custom endpoint a consumer wrote.

## 7. Error handling

**Error responses are never cached, with no special-casing.** `Middleware::RaiseError`
raises before `Response.from_faraday_response` runs, so a 404 or 500 never produces a
value this layer could store. Worth an explicit regression test so a future middleware
reorder cannot silently start caching errors.

**Cache backend failures must not break requests.** A store that raises on read (Redis
down, connection pool exhausted) is logged at `warn` through `api_module.logger` and
treated as a miss. A store that raises on write is logged and ignored; the response is
still returned. A cache outage degrades to an uncached client, never to an error.

The one deliberate exception is the explicit bulk-expiry methods in §9, which raise
`CacheError` when the backend cannot support them.

## 8. Instrumentation

`request.<INSTRUMENTATION_KEY>` gains a `cache` key: `:hit`, `:miss`, or `:bypass`.

```ruby
ActiveSupport::Notifications.subscribe("request.my_api") do |*, payload|
  payload[:cache]   # :hit | :miss | :bypass | nil (resource not cacheable)
  payload[:status]  # 200 — replayed from the cache entry on a hit
  payload[:method]
  payload[:path]
end
```

- A **hit** is emitted by the caching layer, since no HTTP request occurs and
  `Client#execute_request` never runs. Status comes from the cache entry.
- A **miss** is emitted by the existing `Instrumentation` module in `Client`, which
  reads a thread-local the caching layer sets immediately before delegating.

That thread-local is the only coupling between the two layers. It is named explicitly
rather than hidden, lives in `Resteze::Caching`, and is save/restored like the bypass
flags.

> **Behavior change for the release.** `request.<key>` previously fired only on real
> HTTP traffic. Once a resource is cacheable, it also fires on hits. Subscribers
> counting this event as "API calls made" must filter on `cache: :hit`. This belongs in
> the CHANGELOG and the upgrade notes, not just in the caching documentation.

## 9. Public API surface

### Module level

```ruby
MyApi.cache_store = store      # config
MyApi.default_ttl  = 60        # config
MyApi.default_cache_ttl(klass) # overridable hook
MyApi.default_cache_scope(klass)
MyApi.uncached      { ... }
MyApi.refresh_cache { ... }
MyApi.clear_cache              # delete_matched("my_api/*") — NEVER store.clear
```

`clear_cache` must never call `store.clear`. With `config.cache_store = Rails.cache`,
`store.clear` wipes the host application's entire cache — sessions, fragments,
everything. `MemCacheStore#clear` is `flush_all` (`mem_cache_store.rb:181`), and
`RedisCacheStore#clear` flushes the database unless a namespace is configured. Scoped
`delete_matched` is the only acceptable implementation.

### Resource level

```ruby
Widget.cache_for(ttl, list: ttl)  # macro
Widget.cache_ttl                  # resolved
Widget.list_cache_ttl             # resolved
Widget.cache_scope                # overridable
Widget.expire_cache(id)           # single key + prefix sweep
Widget.expire_cache_all           # delete_matched("my_api/widget/*")
```

`cache_for` is backed by `class_attribute` so subclasses inherit and can override.
A sentinel (`:unset`) distinguishes "not declared" from an explicit `cache_for nil`.

### The `delete_matched` capability gap

`ActiveSupport::Cache::Store` is a uniform *interface*, not a uniform *capability set*.
Verified against `activesupport 8.1.3`:

```
cache.rb:732  def delete_matched(matcher, options = nil)
cache.rb:733    raise NotImplementedError.new("#{self.class.name} does not support delete_matched")
```

Implemented by `file_store.rb`, `memory_store.rb`, `redis_cache_store.rb`,
`null_store.rb`, `strategy/local_cache.rb`. **Not** implemented by
`mem_cache_store.rb` — Memcached's protocol has no key enumeration.

`read`, `write`, `delete`, `fetch`, and `clear` are genuinely portable; the entire hot
path is store-agnostic. Only bulk deletion leaks the backend.

Capability cannot be feature-detected: every store `respond_to?(:delete_matched)`
because the base class defines it. Detection means `rescue NotImplementedError`.

`Caching::Store#delete_matched` therefore takes a `strict:` flag:

- `strict: true` (explicit `expire_cache_all` / `clear_cache`) — rescue and re-raise as
  `CacheError`: `"MemCacheStore does not support delete_matched; use expire_cache(id) or
  configure a store that supports key enumeration"`
- `strict: false` (implicit post-write sweep) — rescue, log at `debug`, continue

## 10. Thread safety

- Bypass flags and the instrumentation hand-off are `Thread.current` keys namespaced
  per api_module, save/restored around their blocks, consistent with
  `Client.active_client`.
- `class_attribute` writes happen at class-definition time, not per request.
- No memoization of resolved TTLs or keys across requests; `cache_scope` is expected to
  vary per thread in multi-tenant deployments, so caching the key would reintroduce the
  cross-tenant leak the scope exists to prevent.
- No memoization of the store either (§1). It is resolved per request so that late
  configuration — a Rails initializer, a runtime `configure` call, a callable
  `cache_store` — takes effect, and so a per-tenant callable can route per thread.

## 11. Testing

Minitest + WebMock, matching the existing suite. `AcmeApi` in `test/test_helper.rb`
gains an `ActiveSupport::Cache::MemoryStore`, a `default_ttl`, and cacheable resources.
Each test resets the store.

| Area | Cases |
|---|---|
| TTL resolution | Each level of both chains; `cache_for nil` disables; subclass inheritance and override |
| Opt-in | `include Cacheable` with no store is a no-op; no mixin means no caching; unconfigured store never writes |
| Configuration | `configure` called after classes load takes effect (the initializer case); a callable `cache_store` is resolved per request, not once; swapping the underlying store mid-suite is observed immediately; re-calling `configure` changes behavior without a reload |
| Key | Same call hits; differing params miss; differing `cache_scope` miss (tenant isolation); differing `api_base` miss; param order does not affect the key; `objects_to_ids` normalization — `retrieve(widget)` and `retrieve(widget.id)` share a key |
| Entry | Round-trips status, headers, and body; `parse_body` override honored on rebuild; `cached?` true on hit, false on miss |
| Method rules | GET cached; POST/PUT/PATCH/DELETE never read or written |
| Eviction | Write evicts the record's GET; param variants evicted on a `delete_matched`-capable store; `NotImplementedError` swallowed on one that is not; lists are not evicted |
| Bypass | `uncached` skips read and write; `refresh_cache` skips read and writes; nesting; restoration after an exception; `uncached` wins when both active |
| Errors | A 500 is not cached; a store raising on read degrades to a miss; a store raising on write still returns the response |
| Bulk expiry | `expire_cache(id)`; `expire_cache_all`; `clear_cache` is scoped and never calls `store.clear`; `CacheError` on a store without enumeration |
| Instrumentation | `cache: :hit` with replayed status; `cache: :miss`; `cache: :bypass`; absent for non-cacheable resources |
| No wire traffic | WebMock asserts a second GET issues no HTTP request — the load-bearing assertion for the whole feature |

Testing helpers for consumers are added to `lib/resteze/testing/`, mirroring the
existing Minitest and RSpec helpers:

- `assert_cached(resource) { ... }` / `refute_cached(...)`
- `with_clean_cache { ... }`

## 12. Documentation

- `docs/CONFIGURATION.md` — `cache_store` (both eager and callable forms) and
  `default_ttl`; the hooks; configuring from a Rails initializer rather than the module
  definition, which the existing examples in that file conflate
- `docs/ADVANCED_USAGE.md` — **replace** the two hand-rolled caching recipes, which this
  feature obsoletes
- `docs/API.md` — `Cacheable`, `cache_for`, the bypass blocks, the expiry methods
- `docs/TESTING.md` — the new helpers
- `README.md` — a short caching section
- `CHANGELOG.md` — the feature, plus the `request.*` instrumentation behavior change
- `sig/resteze.rbs` — signatures for the new public surface

A prominent note on `cache_scope` and multi-tenancy. The default is safe for
single-tenant consumers and a data leak for multi-tenant ones who never read the docs;
this is the sharpest edge in the feature and the documentation must say so plainly.

## Deferred

| Item | Why deferred |
|---|---|
| Generation counters for list invalidation | Costs a cache read per lookup; TTL is the accepted answer for list staleness |
| ETag / `Cache-Control` revalidation | Out of scope; nothing here precludes a later `revalidate: true` |
| Per-call keyword arguments (`retrieve(42, uncached: true)`) | Block form covers it without touching signatures or breaking custom endpoints |
| Negative caching (caching 404s) | Errors raise before a `Response` exists; would need its own design |
| A warning when `Cacheable` is included with no store | The silent no-op is a real failure mode; revisit after the first release if it bites |
