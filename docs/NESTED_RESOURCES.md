# Nested Resources

Some resources only exist under a parent:

```
GET  /catalogs/:catalog_name/items
GET  /catalogs/:catalog_name/items/:id
POST /catalogs/:catalog_name/items/:id/archive
```

Declare the path once with `path_template`. `retrieve`, `list`, `save`,
`refresh` and every custom action then route under it, with nothing to
override.

```ruby
module WidgetApi
  include Resteze

  class Item < ApiResource
    include WidgetApi::List
    include WidgetApi::Save

    property :id
    property :price

    path_template "catalogs/:catalog_name/items"

    action :archive, method: :post, on: :member
    action :bulk_update, method: :post
  end
end
```

## Table of Contents

- [The template](#the-template)
- [Calling a nested resource](#calling-a-nested-resource)
- [What an instance remembers](#what-an-instance-remembers)
- [Actions](#actions)
- [The parent reference](#the-parent-reference)
- [Errors](#errors)
- [Testing](#testing)

## The template

- The template is the resource's whole path, in place of its slug. The service
  path and API version still go in front, and the id still goes behind.
- A segment written `:name` is a **path value** that each call fills in. A
  token is a whole segment and is named like a method (`:catalog_name`).
  Everything else is used as written.
- Any number of tokens is allowed:
  `path_template "catalogs/:catalog_name/items/:item_id/variants"`.
- Subclasses inherit the template and may declare their own.
- `Item.path_template` returns the template and `Item.path_params` its token
  names, `[:catalog_name]`.
- `Item.nested?` is true for a resource with a template and false for any
  other. Instances answer it too (`item.nested?`).
- `resource_slug` is unchanged (`"items"`), so defaults derived from it, such
  as the id param name, stay the same.

These are rejected with an `ArgumentError` when the class is loaded:

| Template | Why |
|---|---|
| `"catalogs/items"` | No tokens. Set `resource_slug` instead. |
| `"a/:x/b/:x"` | A token is repeated. |
| `"things/:id/parts"` | `id`, `params`, `values` and `parent` are reserved. |
| `"catalogs/v:version/items"` | A token must be a whole segment. |
| `"stores/:key/items"` | The reader `#key` would shadow an existing method. Resources are Hashes, so pick another name, such as `:store_key`. |

## Calling a nested resource

Path values are keywords, separate from request params:

```ruby
WidgetApi::Item.list(catalog_name: "shoes", params: { cursor: "abc" })
# => GET /catalogs/shoes/items?cursor=abc

WidgetApi::Item.retrieve("sku1", catalog_name: "shoes")
# => GET /catalogs/shoes/items/sku1

WidgetApi::Item.new(catalog_name: "shoes", values: { price: 10 }).save
# => POST /catalogs/shoes/items        body: {"price":10}

WidgetApi::Item.new("sku1", catalog_name: "shoes", values: { price: 12 }).save
# => PUT /catalogs/shoes/items/sku1
```

Path values are percent-encoded the same way the id is (`"red shoes"` is sent
as `red%20shoes`), and they never appear in the query string or the request
body.

The hash form of `retrieve` works too. Path values are taken out first and the
rest is the id and its extra params:

```ruby
WidgetApi::Item.retrieve(id: "sku1", catalog_name: "shoes", expand: true)
# => GET /catalogs/shoes/items/sku1?expand=true
```

A keyword that is not one of the template's tokens raises `ArgumentError`, as
any unknown keyword does. A resource with no template accepts no path
keywords at all.

## What an instance remembers

Every instance keeps the path values it was built with, so it can route by
itself later:

```ruby
items = WidgetApi::Item.list(catalog_name: "shoes")
item  = items.first

item.catalog_name   # => "shoes"
item.path_params    # => { catalog_name: "shoes" }  (frozen)
item.refresh        # => GET /catalogs/shoes/items/sku1
item.save           # => PUT /catalogs/shoes/items/sku1
```

- Items in a list get the path values of the `list` call that produced them.
  So do the results of actions that return this resource (`returns: :self`,
  `returns: :list`, or the class itself). Results of any other class do not.
- The values live beside the properties, not in them. They are not part of
  `as_json` or the save body.
- `refresh` and `save` leave them in place.
- One reader is generated per token.

If the API echoes the parent's id in the body and you declare it as a
property, the property keeps its reader. For routing, a value passed
explicitly wins and the property is the fallback:

```ruby
class Field < ApiResource
  property :id
  property :catalog_name
  path_template "catalogs/:catalog_name/fields"
end

Field.new("f1", values: { catalog_name: "shoes" }).resource_path
# => "/catalogs/shoes/fields/f1"
```

## Actions

Custom actions nest like the built-ins, including re-routed ones and those
that carry the id as a param.

```ruby
WidgetApi::Item.bulk_update(catalog_name: "shoes", items: [...])
# => POST /catalogs/shoes/items/bulk_update     body: {"items":[...]}

WidgetApi::Item.archive("sku1", catalog_name: "shoes", reason: "old")
# => POST /catalogs/shoes/items/sku1/archive    body: {"reason":"old"}

item.archive(reason: "old")
# => the same request, using the values the item remembers
```

The class forms read the template's tokens (and `parent:`) from their keywords
as path values; everything else is a request param.

The instance form never takes path values. Every keyword is a request param,
which is also how you send a param that shares a token's name:

```ruby
item.move(catalog_name: "boots")
# => POST /catalogs/shoes/items/sku1/move       body: {"catalog_name":"boots"}
```

## The parent reference

Resteze has no associations. The parent side is a method you write, and it can
hand itself over with `parent:`:

```ruby
class Catalog < ApiResource
  property :name

  def items(params: {})
    Item.list(catalog_name: name, parent: self, params:)
  end
end

catalog.items.first.parent.equal?(catalog)   # => true
```

- `parent:` is accepted wherever path values are: `list`, `retrieve`, `new`
  and the class forms of actions.
- It travels with the path values: every item in a list gets it, and it
  survives `refresh` and `save`.
- It is only a reference. Resteze never fetches it, never serializes it, and
  never reads path values from it, so pass those as well.
- `item.parent` is `nil` when none was given.
- If the resource declares a property named `parent`, the property keeps that
  reader and the reference is available as `item.path_parent`.

## Errors

A path value may be missing when an object is built. It is checked when a
path is needed, before any request is sent:

```ruby
WidgetApi::Item.list
# => WidgetApi::InvalidRequestError, param: "catalog_name"

WidgetApi::Item.new("sku1").refresh
# => WidgetApi::InvalidRequestError, param: "catalog_name"
```

A blank value (`nil` or `""`) counts as missing. So does `"."` or `".."`, which a URL would
resolve as a directory step out of the template's path.

## Testing

`has_action ... path:` fills each token with its upcased name, the way it uses
`"ID"` for the id:

```ruby
describe WidgetApi::Item do
  include Resteze::Testing::Minitest::Object

  subject { WidgetApi::Item }

  it "routes its actions" do
    has_action :retrieve, path: "/catalogs/CATALOG_NAME/items/ID"
    has_action :archive, method: :post, on: :member, path: "/catalogs/CATALOG_NAME/items/ID/archive"
    has_action :bulk_update, path: "/catalogs/CATALOG_NAME/items/bulk_update"
  end
end
```
