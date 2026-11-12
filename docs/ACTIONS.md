# Actions

Resteze assumes a textbook REST surface by default: `GET /widgets`,
`GET /widgets/:id`, `POST /widgets`, `PUT /widgets/:id`. Many APIs do not look
like that. Some address endpoints by action name instead of by id in the path
(`GET /campaigns/list`, `GET /campaigns/details?campaign_id=…`,
`POST /users/track`), and almost every API has a few endpoints that fit no
pattern at all.

The `action` DSL, modeled on the Rails routing DSL for custom resource actions,
covers both. A resource declares the actions it supports; each action resolves to
an HTTP method, a path and a return type. The built-in `retrieve`, `list`,
`create` and `update` are ordinary actions with REST defaults, so re-routing one
uses the same vocabulary as adding a new one.

**A resource that declares nothing behaves exactly as it did before.**

## Table of Contents
- [Declaring custom actions](#declaring-custom-actions)
- [Collection and member actions](#collection-and-member-actions)
- [Re-routing the built-in actions](#re-routing-the-built-in-actions)
- [API-wide defaults](#api-wide-defaults)
- [Lookup order](#lookup-order)
- [Return values](#return-values)
- [Hooks](#hooks)
- [Introspection](#introspection)
- [Testing](#testing)
- [The escape hatch](#the-escape-hatch)

## Declaring custom actions

```ruby
module MyApi
  include Resteze

  class User < ApiResource
    property :external_id

    action :track,      method: :post
    action :identify,   method: :post
    action :export_ids, method: :post, path: "export/ids"
  end
end

MyApi::User.track(events: [{ external_id: "u1", name: "rented_movie" }])
# => POST /users/track with a JSON body

MyApi::User.export_ids(external_ids: ["u1"])
# => POST /users/export/ids
```

Each declaration generates a method named after the action. Params are passed as
keyword arguments and sent the way the client always sends them: GET, HEAD and
DELETE put them in the query string; everything else sends a JSON body.

| Option | Values | Default | Meaning |
|---|---|---|---|
| `method:` | any HTTP verb symbol | required | HTTP method |
| `on:` | `:collection`, `:member` | `:collection` | Whether the action addresses the collection or one record |
| `path:` | string | the action name | Segment appended after the resource slug (and after the id for `id: :path`). May contain `/`; each part is URL-escaped. `nil` means no segment |
| `id:` | `:path`, `:param` | `:path` | Member actions only. Whether the id goes in the path or is sent as a param |
| `id_param:` | symbol | singular slug + `_id` | Member actions with `id: :param`. The param key that carries the id |
| `returns:` | `nil`, `:self`, `:list`, an `Object` subclass | `nil` | What the generated method returns; see [Return values](#return-values) |
| `as:` | symbol | the action name | The Ruby method name to generate; use it when the action name collides with an existing method |

Unknown options raise `ArgumentError` when the class is loaded, as does `id:` on a
collection action, `returns: :list` on a class that does not include `List`, and
an action whose method name already exists on the class:

```ruby
action :send, method: :post               # ArgumentError: Object#send exists; pass as:
action :send, method: :post, as: :deliver # MyApi::Message.deliver(...)
action :delete, method: :post, on: :member, as: :destroy
```

## Collection and member actions

A collection action generates a class method. A member action generates an
instance method, plus a class method that takes the id first, mirroring
`retrieve(id)`:

```ruby
class Campaign < ApiResource
  property :id
  property :name

  action :data_series, method: :get                       # collection
  action :duplicate,   method: :post, on: :member         # member
end

MyApi::Campaign.data_series(length: 7)    # GET  /campaigns/data_series?length=7
campaign.duplicate(name: "copy")          # POST /campaigns/abc/duplicate
MyApi::Campaign.duplicate("abc", name: "copy")   # same request
```

Where the id goes is controlled by `id:`:

| `id:` | Request |
|---|---|
| `:path` (default) | `POST /campaigns/abc/duplicate` |
| `:param` | `POST /campaigns/duplicate` with `campaign_id: "abc"` merged into the body |

With `id: :param`, the id is merged in under `id_param` (default `campaign_id`
for the slug `campaigns`). A param you pass with the same key wins. Calling a
member action on a record with a blank id raises `MyApi::InvalidRequestError`.

## Re-routing the built-in actions

Four names are reserved and pre-registered with REST defaults:

| Name | Method | Scope | Path | Id |
|---|---|---|---|---|
| `retrieve` | GET | member | none | `:path` |
| `list` | GET | collection | none | n/a |
| `create` | POST | collection | none | n/a |
| `update` | PUT | member | none | `:path` |

Redeclaring one replaces its route. Options you leave out fall through to the
next level of the [lookup order](#lookup-order), so changing just the path is one
line. The existing `retrieve`, `list` and `save` methods keep their behavior and
only pick up the new route; no new method is generated for a reserved name.

```ruby
class ContentBlock < ApiResource
  include List
  include Save

  property :id

  action :retrieve, path: "info",   id: :param   # GET  /content_blocks/info?content_block_id=…
  action :list,     path: "list"                 # GET  /content_blocks/list
  action :create,   path: "create"               # POST /content_blocks/create
  action :update,   path: "update", method: :post, id: :param
  # => POST /content_blocks/update with content_block_id in the body
end
```

## API-wide defaults

When a whole API follows one convention, declare it once on the module. The same
`action` call is available there and supplies defaults for every resource;
`action_defaults` sets the lowest-priority defaults for every action at once.

```ruby
module MyApi
  include Resteze

  action_defaults id: :param          # all member actions carry the id as a param

  action :retrieve, path: "details"
  action :list,     path: "list"
  action :create,   path: "create"
  action :update,   path: "update", method: :post
end

class Campaign < ApiResource
  include List
  property :id
end

MyApi::Campaign.retrieve("abc")   # GET /campaigns/details?campaign_id=abc
MyApi::Campaign.list              # GET /campaigns/list

class ContentBlock < ApiResource
  action :retrieve, path: "info"  # the one outlier
end
```

`action_defaults` accepts `method:`, `id:` and `id_param:`. A module-level
declaration of a custom name supplies defaults only; it does not generate a method
on any resource. A resource that wants the action declares it, with or without
options:

```ruby
module MyApi
  action :export, method: :post
end

class User < ApiResource
  action :export      # POST /users/export, method supplied by the module
end
```

Routing options (`method:`, `path:`, `id:`, `id_param:`, `returns:`) are resolved
when an action is used, not when it is declared, so module-level calls made in a
Rails initializer after resource classes are loaded still take effect. The two
options that shape the generated method, `on:` and `as:`, are read when the
resource declares the action, so set them at module level before the resource
classes load, or on the resource itself.

## Lookup order

An action's options are merged lowest priority first:

1. REST built-in defaults, for the four reserved names.
2. The module's `action_defaults`.
3. The module's `action` declaration for that name.
4. Each ancestor resource class's declaration, farthest first.
5. The resource's own declaration.

Subclasses inherit every action of their parent and can override individual
options. The resource slug is still derived per class, so a subclass routes under
its own slug unless it overrides `resource_slug`.

## Return values

| `returns:` | Result |
|---|---|
| omitted | `MyApi::Result`, a loose [Hashie::Mash](https://github.com/hashie/hashie#mash) of the response body |
| `:self` | one resource built from a Hash body, or an Array of resources from an Array body |
| `:list` | a `MyApi::ListObject` built with the resource's `list_key` |
| an `Object` subclass | as `:self`, with that class |

```ruby
class User < ApiResource
  action :track, method: :post
end

result = MyApi::User.track(events: [...])
result.message                    # => "success"
result.events_processed           # => 2
result.http_response.http_status  # => 200

class TrackResult < Object
  property :message
  property :events_processed
end

class User < ApiResource
  action :track, method: :post, returns: TrackResult
end
```

`MyApi::Result` is created by `include Resteze` alongside `Object`, `Client`,
`Response` and the other namespaced classes, so the name `Result` is reserved
inside your API module from 0.5.0 on.

`Result` never raises on body shape. A `204 No Content`, an empty body, or a
non-JSON body with a non-JSON content type yields an empty `Result`; the raw
parsed body is always at `result.http_response.data`.

`:self` on a member action builds a **new** instance and leaves the receiver
untouched. Mutating the receiver remains the job of `refresh` and `save`.

When the resource has an `object_key`, a Hash body is treated as an envelope and
unwrapped the way `refresh` does, while each element of an Array body is treated
as a bare item the way `ListObject` does.

## Hooks

Generated action methods pass their params and headers through two overridable
class methods, mirroring `list_params` and `list_headers`:

```ruby
class User < ApiResource
  action :track, method: :post

  def self.action_params(name, params)
    params.merge(api_key: MyApi.api_key)
  end

  def self.action_headers(name, params)
    { "X-Request-Source" => "my-app" }
  end
end
```

The built-ins expose their routed paths as overridable methods too:

| Method | Used by |
|---|---|
| `retrieve_resource_path` (instance) | `refresh` |
| `list_resource_path(params)` (class) | `list` |
| `save_resource_path` (instance) | `save` |
| `save_params` (instance) | `save`; `as_save_json` plus the id param when `update` uses `id: :param` |
| `id_param` (class) | the default id param for every member action on the class |

The instance method `resource_path` is unchanged. It still means "this record's
REST path" (`/campaigns/abc`), so hand-rolled requests built on it keep working
even when `retrieve` is re-routed.

## Introspection

```ruby
MyApi::Campaign.actions                 # => { retrieve: #<Resteze::Action>, list: ..., ... }
MyApi::Campaign.actions.fetch(:retrieve).http_method   # => :get
MyApi::Campaign.actions.fetch(:retrieve).path_for("abc") # => "/campaigns/details"
MyApi::Campaign.actions.fetch(:duplicate).to_h
# => { name: :duplicate, method: :post, on: :member, path: "duplicate", id: :param,
#      id_param: :campaign_id, returns: nil, as: :duplicate }
```

`actions` is rebuilt on every call and frozen. `action_for(:retrieve)` resolves a
single action and is what `refresh`, `list`, `save` and the generated methods use
internally, so a resource that already defines its own `actions` class method
keeps working. `action` is always a declaration, never a lookup.

## Testing

The Minitest and RSpec helpers gain `has_action`, which asserts an action is
declared and checks any options you pass. `path:` is compared against the full
routed path, using the id `"ID"` for member actions.

```ruby
describe MyApi::Campaign do
  include Resteze::Testing::Minitest::Object

  subject { MyApi::Campaign }

  it "routes its actions" do
    has_action :data_series, method: :get, on: :collection, path: "/campaigns/data_series"
    has_action :duplicate, method: :post, on: :member, id: :param, path: "/campaigns/duplicate"
    has_action :retrieve, path: "/campaigns/details"
  end
end
```

## The escape hatch

Anything the DSL does not express is still one `request` call away, exactly as
before:

```ruby
class User < ApiResource
  def update_with_version(version, attributes)
    request(:patch, resource_path, params: attributes, headers: { "If-Match" => version })
  end
end
```
