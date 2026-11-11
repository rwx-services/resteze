# Resteze Actions — Design

- **Date:** 2026-11-11
- **Status:** Draft, pending approval (caching sequencing confirmed: caching moves to 0.6.0)
- **Target version:** 0.5.0

## Context and Intent

Resteze assumes a textbook REST surface: `GET /widgets`, `GET /widgets/:id`,
`POST /widgets`, `PUT /widgets/:id`. Many real APIs do not look like that. Braze,
the motivating example, calls itself REST but addresses most endpoints by action
name rather than by id in the path: `GET /campaigns/list`,
`GET /campaigns/details?campaign_id=…`, `POST /users/track`, `POST /messages/send`,
`POST /content_blocks/update`. A few corners of the same API (catalogs, data
objects, SCIM) are genuinely id-in-path REST, so a Braze client needs both styles
side by side.

Today a consumer handles this by overriding `resource_path`, `list_resource_path`
and `save_resource_path` by hand, and by writing each extra endpoint as a bespoke
class or instance method that calls `request` with a string-built path.
`docs/ADVANCED_USAGE.md` and `docs/API.md` already document that pattern
(`activate!`, `search`, `featured`). It works, but every consumer re-invents the
same three lines, and the built-in actions have no declarative way to be re-routed.

This design adds an **action routing DSL** to `ApiResource`, modeled on the Rails
routing DSL for custom resource actions. A resource declares the actions it
supports; each action resolves to an HTTP method, a path, and a return type. The
built-in `retrieve`, `list`, `create` and `update` become ordinary actions with
REST defaults, so they can be re-routed with the same vocabulary used to add new
ones.

The result keeps the Resteze mental model intact: everything is still a resource,
`Braze::Campaign.list` and `Braze::Campaign.retrieve(id)` still read the way they
do in every other Resteze client, and an API's outliers like `Braze::User.track`
are declared in one line on the resource they belong to.

### Success criteria

1. A resource with no action declarations behaves **exactly** as it does in 0.4.0.
   Same paths, same methods, same params, same return values. The existing test
   suite passes unchanged.
2. A consumer can re-route a built-in action with one line on the resource, or once
   for the whole API module, and `retrieve`, `list` and `save` honor it.
3. A consumer can declare a new collection or member action in one line and get a
   working class or instance method that goes through `request`, so the client,
   logging, instrumentation, error middleware and thread-local client swapping all
   apply.
4. The existing override points (`resource_path`, `list_resource_path`,
   `save_resource_path`, `retrieve_params`, `list_params`, `*_headers`) keep working
   and keep their meaning.
5. Zero new runtime dependencies.

### Non-goals

- **A separate gem.** Earlier framings (`resteze-rpc`, `Resteze::RPC`) were
  rejected. This ships in core as 0.5.0 because it replaces the internals of
  `ApiResource`, `List` and `Save`; a wrapper gem would have to reach into those.
- **JSON-RPC, XML-RPC, or any envelope protocol.** This is about path routing on
  HTTP, nothing more.
- **Interpreting response envelopes.** Braze returns `message: "success"` and an
  optional `errors` array on 2xx responses. The DSL does not raise, warn, or
  otherwise interpret those. They land in the result object or the resource's
  property bag and metadata, and a consumer who wants stricter behavior adds
  Faraday middleware as they do today.
- **Pagination.** Page-based or cursor-based iteration over `list` is a consumer
  concern, as it is in 0.4.0.
- **A built-in `delete` / `destroy` action.** Resteze 0.4.0 has no delete mixin.
  Consumers declare `action :delete, method: :delete, on: :member` if they need it.
  A first-class `Destroy` mixin can follow in a later release.
- **Nested resources** (`/posts/:post_id/comments`). The existing `resource_path`
  override recipe in `docs/API.md` remains the way to do this. The action path
  builder calls `resource_path`, so nested overrides still compose with actions.

## Decisions

| # | Decision | Rationale |
|---|---|---|
| 1 | Ship in `resteze` core as 0.5.0 | Replaces the route resolution inside `ApiResource`, `List`, `Save`; cannot be layered cleanly from outside |
| 2 | Vocabulary is `action`, `on: :collection` / `on: :member` | Rails routing DSL; immediately familiar to the gem's audience, and the true description of what Braze does |
| 3 | Built-ins (`retrieve`, `list`, `create`, `update`) are actions with REST defaults | One mechanism for routing; re-routing a built-in uses the same `action` call as adding a new one |
| 4 | Module-level `action` declarations act as API-wide defaults | Braze is consistent across resources; declaring `details` once beats repeating it on 30 classes |
| 5 | Lookup order: resource class → superclass chain → API module defaults → REST built-ins | Subclasses inherit; module sets the house style; a resource overrides only its outliers |
| 6 | Member id placement is `:path` by default, `:param` opt-in | `:path` is REST and Rails; `:param` is what Braze needs; the API module can flip the default once |
| 7 | Id param name defaults to singular slug plus `_id` | `campaigns` → `campaign_id` matches Braze and most verb-style APIs; overridable per action and per resource |
| 8 | Custom actions return a loose `Result` object unless `returns:` says otherwise | Many action responses are status payloads, not resources; forcing a type per action is friction with no payoff |
| 9 | Custom action methods take `**params`; headers come from an overridable hook | `User.track(events: [...])` must read naturally; mirrors the existing `list_params` / `list_headers` hook style |
| 10 | Built-in actions keep their existing method bodies and only consult the registry for routing | `refresh` still mutates `self`, `save` still merges; nothing about their semantics changes |
| 11 | `Result` is a `Hashie::Mash` subclass | Loose, dot-accessible, deep; the gem already depends on Hashie |

## The DSL

### Declaring actions on a resource

```ruby
module Braze
  include Resteze

  class Campaign < ApiResource
    include List

    property :id
    property :name

    action :data_series, method: :get,  on: :collection
    action :duplicate,   method: :post, on: :member
  end

  class User < ApiResource
    property :external_id

    action :track,      method: :post
    action :identify,   method: :post
    action :export_ids, method: :post, path: "export/ids"
  end
end

Braze::Campaign.data_series(length: 7)    # GET  /campaigns/data_series?length=7
Braze::Campaign.duplicate("abc", name: "copy")
campaign.duplicate(name: "copy")          # POST /campaigns/abc/duplicate (REST default id placement)
Braze::User.track(events: [...])          # POST /users/track
Braze::User.export_ids(external_ids: [])  # POST /users/export/ids
```

`action` accepts:

| Option | Values | Default | Meaning |
|---|---|---|---|
| `method:` | any Faraday verb symbol | required for custom actions | HTTP method |
| `on:` | `:collection`, `:member` | `:collection` | Whether the action addresses the collection or one resource |
| `path:` | string | the action name | Path segment appended after the resource slug (and after the id when id placement is `:path`). `nil` or `""` means no segment |
| `id:` | `:path`, `:param` | `:path` | Member actions only. Where the resource id goes |
| `id_param:` | symbol | singular slug + `_id` | Member actions with `id: :param` only. The param key that carries the id |
| `returns:` | `nil`, `:self`, `:list`, an `Object` subclass | `nil` | What the generated method returns; see "Return values" |
| `as:` | symbol | the action name | The Ruby method name to generate. Use when the action name collides with an existing method, e.g. `action :send, method: :post, as: :deliver` |

Unknown options raise `ArgumentError` at declaration time. Declaring `id:` or
`id_param:` on a collection action raises `ArgumentError`.

`path:` may contain `/`. It is split on `/` and each part is `CGI.escape`d, so
`path: "export/ids"` yields `/users/export/ids`.

### Re-routing built-in actions

Four action names are reserved and pre-registered with REST defaults:

| Name | `method` | `on` | `path` | `id` |
|---|---|---|---|---|
| `retrieve` | `:get` | `:member` | none | `:path` |
| `list` | `:get` | `:collection` | none | n/a |
| `create` | `:post` | `:collection` | none | n/a |
| `update` | `:put` | `:member` | none | `:path` |

Redeclaring one of these names on a resource replaces its route. Options not given
fall back to the next level in the lookup chain, so a resource can change just the
path segment:

```ruby
class ContentBlock < ApiResource
  include List
  include Save

  action :retrieve, path: "info"     # GET /content_blocks/info?content_block_id=…
  action :list,     path: "list"     # GET /content_blocks/list
  action :create,   path: "create"   # POST /content_blocks/create
  action :update,   path: "update", method: :post   # POST /content_blocks/update, id in body
end
```

Redeclaring a built-in does **not** generate a new method. `retrieve`, `list` and
`save` keep their existing bodies and consult the registry for the route. This is
decision 10.

### API-wide defaults on the module

The same `action` call is available on the including module and sets defaults for
every resource in that API:

```ruby
module Braze
  include Resteze

  action_defaults id: :param

  action :retrieve, path: "details"
  action :list,     path: "list"
  action :create,   path: "create"
  action :update,   path: "update", method: :post
end
```

`action_defaults` takes any subset of `method:`, `id:`, `id_param:` and applies
them as the lowest-priority defaults for every action in the module. In practice
its purpose is `id: :param`, which flips the whole API to Braze's style in one line.

Module-level `action` may name a custom action as well as a built-in. A custom
action declared at module level is not generated on any resource; it only supplies
defaults for a resource that declares an action of the same name. This keeps
generation explicit at the class that owns the endpoint.

### Lookup chain

When a resource resolves an action by name, options are merged lowest priority
first:

1. REST built-in defaults for that name (only for the four reserved names).
2. The module's `action_defaults`.
3. The module's `action` declaration for that name, if any.
4. Each ancestor `ApiResource` subclass's declaration for that name, nearest last.
5. The resource's own declaration.

A subclass therefore inherits every action of its parent and can override
individual options. A subclass redeclaring an action does not affect its parent.

**Resolution is lazy.** The chain is walked when an action is resolved, not when
it is declared. Each class stores only its own declarations; ancestors are walked
at resolution time rather than copied on `inherited`. This means module-level
`action` and `action_defaults` calls made after resource classes are loaded, as in
a Rails initializer, still take effect, matching how `default_resource_slug` and
the other `default_*` hooks already behave. `Klass.actions` may be memoized only
if the memo is invalidated by any later declaration anywhere in the chain; the
simplest correct implementation is not to memoize.

Validation is split accordingly. Unknown options, `id:` on a collection action,
`:list` without `List`, and method-name collisions are checked at declaration time
because they do not depend on the chain. The presence of `method:` is checked at
resolution time, because a resource may legitimately declare `action :track` with
no options and rely on the module to supply the method; a missing method raises
`ArgumentError` naming the action and the class on first use.

### Path resolution

Given a resolved action and, for member actions, an id:

```
base    = on == :member && id == :path ? resource_path(id) : resource_path
segment = path (nil for built-ins unless re-routed)
full    = segment.present? ? [base, segment].join("/").squeeze("/") : base
```

`resource_path` is the resource's existing class method, so every existing
override of it, including nested-resource overrides and the zero-arity override in
the gem's own test helper, continues to shape action paths. `segment` is
`CGI.escape`d the same way ids are today.

Worked examples with slug `campaigns` and id `abc`:

| Action | `id` | `path` | Result |
|---|---|---|---|
| `retrieve` | `:path` | none | `/campaigns/abc` |
| `retrieve` | `:param` | `details` | `/campaigns/details` with `campaign_id=abc` in query |
| `duplicate` | `:path` | `duplicate` | `/campaigns/abc/duplicate` |
| `duplicate` | `:param` | `duplicate` | `/campaigns/duplicate` with `campaign_id=abc` in body |
| `list` | n/a | none | `/campaigns` |
| `list` | n/a | `list` | `/campaigns/list` |

Whether the id param lands in the query string or the JSON body is decided by the
existing `Client#process_params` rule: GET, HEAD and DELETE put params in the
query; everything else puts them in the body. The DSL does not add a second rule.

### Id param merging

For a member action with `id: :param`, the generated method (or `refresh` / `save`
for built-ins) merges `{ id_param => id }` into the request params before any
consumer-supplied params. Consumer params win on key collision. The resource's
`id` is read from the instance the same way `resource_path` reads it today, and a
blank id raises the same `InvalidRequestError` that `resource_path` raises now.

`id_param` resolves, in order: the action's `id_param:` option; the resource class
method `id_param` if the consumer defined one; the API module's `default_id_param(klass)`
hook, whose default is `resource_slug.singularize + "_id"` symbolized.

### Generated methods

For each **custom** action declared on a resource class:

- `on: :collection` defines a class method `Klass.name(**params)`.
- `on: :member` defines an instance method `resource.name(**params)` and a class
  method `Klass.name(id, **params)` that is `new(id).name(**params)`. The class
  form mirrors `retrieve(id)`.

Both forms obtain headers from a class method `action_headers(name, params)`,
default `{}`, and pass params through `action_params(name, params)`, default
identity. Consumers override these the way they override `list_params` and
`list_headers` today. These two hooks are the only per-action customization point
beyond the declaration itself; a consumer who needs more defines the method by
hand as before.

Declaring an action whose generated method name (the `as:` value, default the
action name) is already defined on the receiver raises `ArgumentError` at
declaration time rather than silently overwriting. The check covers **all**
methods, core Ruby and Hashie included, not only consumer-defined ones: a
collection action generates on the class, where `send` is `Object#send`, and a
member action generates on instances, which are `Hash`es, so `delete`, `update`,
`select` and friends all collide. The error message names the colliding method
and suggests `as:`. The four reserved names are exempt because they never
generate. So Braze's `POST /messages/send` is declared as
`action :send, method: :post, as: :deliver` and a verb-style delete as
`action :delete, method: :post, on: :member, as: :destroy`.

### Return values

| `returns:` | Collection action | Member action |
|---|---|---|
| omitted | `api_module::Result` built from `response.data` | same |
| `:self` | one resource via `construct_from(data)` when `data` is a Hash; an array of resources via `util.convert_to_object(data, self)` when it is an Array | a **new** instance of the resource class; the receiver is not mutated |
| `:list` | `construct_list_from(data)`, i.e. a `ListObject` using the resource's `list_key` | same |
| an `Object` subclass | as `:self`, with `klass` in place of `self` | same |

The Hash/Array split matters when the target class has an `object_key`. A Hash
response is treated as an envelope and goes through `construct_from`, which
unwraps `object_key` the same way `refresh` does. Array elements are treated as
bare items and go through `util.convert_to_object`, which wraps each one in
`object_key` the same way `ListObject` does. Using `convert_to_object` on a Hash
envelope would nest the key twice and yield an empty object.

When `response.data` is not a Hash, which is the case for a `204 No Content`
body, a redirect, or a non-JSON body, the default `Result` is empty apart from
`http_response`. The raw parsed body is always reachable as
`result.http_response.data`. `Result` never raises on body shape.

`:list` on a class without `List` included raises `ArgumentError` at declaration
time.

`api_module::Result` is a new namespaced constant created in the `included` block,
a subclass of `Resteze::Result < Hashie::Mash` with `ApiModule` mixed in. It
exposes the parsed body with dot access and carries the `Resteze::Response` it was
built from in a reader named `http_response`, so status and headers are reachable
without a second request. Hashie's method-name collision warnings are disabled on
this class.

### Introspection

- `action` always declares. It is never a lookup, so `action :track` with no
  options on a resource is a declaration that leans on module defaults, not an
  introspection call.
- `Klass.actions` returns a frozen hash of name → resolved action for every action
  visible to the class, built-ins included. `Klass.actions.fetch(:track)` is the
  introspection idiom; there is no separate `action(name)` reader.
- A resolved action is a plain value object with readers for every option plus
  `name`. It responds to `path_for(id = nil)` and `to_h`. This is what the testing
  helpers assert against.

### Built-in integration

- `ApiResource#resource_path` (instance) is **unchanged**. It still means "this
  record's REST path", `self.class.resource_path(id)`, because consumer code and
  the docs build strings like `"#{resource_path}/activate"` on it. Re-routing
  `retrieve` must not change what that string means.
- `refresh` instead calls a new public instance method `retrieve_resource_path`,
  which returns `self.class.actions.fetch(:retrieve).path_for(id)` and is
  overridable like `list_resource_path` and `save_resource_path`.
  `retrieve_params` merges the id param when placement is `:param`.
  `retrieve_method` returns the resolved `retrieve` action's method.
- `List.list_resource_path(params)` becomes `action(:list).path_for`.
  `list_method` returns `action(:list).method`.
- `Save#save_method` returns `action(persisted? ? :update : :create).method`.
  `save_resource_path` returns the matching `path_for(id)`. `as_save_json` is
  merged with the id param for `update` when placement is `:param`.

Every one of those methods remains public and overridable, and a consumer override
still wins, because the built-in bodies call the method, not the registry
directly.

### Testing helpers

`Resteze::Testing::Minitest` and `Resteze::Testing::RSpec` gain one helper each,
mirroring `has_property`:

```ruby
has_action :track, method: :post, on: :collection, path: "/users/track"
```

It asserts the resolved action's options and, when `path:` is given, the result
of `path_for` (with a fixed id of `"ID"` for member actions). The exact assertion
API is left to the builder; it should read like `has_property`.

## Interaction with the caching design

`docs/superpowers/specs/2026-10-16-resteze-caching-design.md` also targets 0.5.0
and intercepts at the `Request` layer. Actions resolve a route and then call
`request`; caching wraps `request`. Nothing in this design assumes caching.

They are not fully independent, though. The caching plan derives record-vs-
collection cache keys and write-time eviction from the shape of the request path.
Under `id: :param`, `retrieve` hits the same path, `/campaigns/details`, for every
id, so path-shape key derivation would collapse every record into one key and
eviction could not find a record. The caching design will need to re-derive keys
from the resolved action and id rather than from the path.

**Sequencing (decided):** actions ships as 0.5.0 and caching moves to 0.6.0. This design
adds no caching affordance; the caching design re-specs key derivation against
`Klass.actions` and the id when it is picked back up. The caching spec's "first
class-level DSL" remark in its decision 6 will no longer be true.

## Deliverables

1. `lib/resteze/action.rb`: the resolved-action value object and option validation.
2. `lib/resteze/actions.rb`: the `action` / `action_defaults` class-level DSL, the
   registry with inheritance and the lookup chain, and method generation. Mixed
   into `ApiResource`'s `ClassMethods`; the module-level half added to
   `Resteze::ClassMethods`.
3. `lib/resteze/result.rb` and the `Result` constant in the `included` block.
4. `ApiResource`, `List`, `Save` reworked to route through the registry.
5. Testing helpers.
6. Tests: registry resolution and inheritance; every row of the path table above;
   generated collection and member methods against WebMock; `returns:` variants;
   built-in re-routing through `retrieve`, `list`, `save`; declaration-time errors;
   and the full existing suite unchanged.
7. Docs: a new `docs/ACTIONS.md`; `docs/API.md` and `docs/ADVANCED_USAGE.md`
   rewritten so the custom-endpoint examples use the DSL and the hand-rolled form is
   shown once as the escape hatch; README feature list; CHANGELOG `[0.5.0]`;
   `CLAUDE.md` architecture section.
8. `VERSION` bumped to `0.5.0`.

## Left to the builder

- Internal representation of the registry (plain hash of hashes vs. structs) and
  how the ancestor walk is implemented.
- Whether `Resteze::Action` is a `Struct`, `Data`, or a plain class.
- Exact wording of `ArgumentError` messages.
- Exact assertion signature of `has_action`.
- Whether `action_defaults` is stored on the module as an instance variable or via
  a `default_action_options` hook; the observable behavior is what is specified.
- Order of the new `require`s in `lib/resteze.rb`.
