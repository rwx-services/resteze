# Resteze Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a Rails-style `action` routing DSL to `ApiResource` so a resource can declare custom collection and member endpoints in one line and re-route the built-in `retrieve`, `list`, `create` and `update` actions, with 0.4.0 behavior unchanged for resources that declare nothing.

**Architecture:** A `Resteze::Action` value object resolves one action's HTTP method, path and return type from a lazy lookup chain (REST built-ins → module `action_defaults` → module `action` declarations → ancestor classes → the class itself). A `Resteze::Actions` concern mixed into `ApiResource` holds per-class declarations, resolves the chain on demand, generates methods for custom actions, and performs the request. `ApiResource`, `List` and `Save` keep their method bodies and consult the registry only for routing. A `Resteze::Result` Mash is the default return for custom actions.

**Tech Stack:** Ruby ≥ 3.2, ActiveSupport::Concern, Hashie 5 (`Hashie::Mash`), Faraday via the existing `Client`, Minitest spec + WebMock, RuboCop.

**Spec:** `docs/superpowers/specs/2026-11-11-resteze-actions-design.md`

## Global Constraints

- Zero new runtime dependencies. The gemspec's dependency list does not change.
- `required_ruby_version >= 3.2.0`; `TargetRubyVersion: 3.2` in RuboCop.
- `bundle exec rake` (tests + RuboCop) passes after every task. RuboCop: 125-column lines, `Metrics/MethodLength` max 15, double-quoted strings, no frozen-string-literal magic comment.
- Every existing test passes unchanged. Existing test files may gain tests but no existing assertion is edited or removed.
- Reserved action names are exactly `retrieve`, `list`, `create`, `update`. They never generate methods.
- Default id param is the singular `resource_slug` plus `_id`, as a symbol (`campaigns` → `:campaign_id`).
- The `Action` reader for the HTTP verb is `http_method`, never `method`, because `Object#method` exists on every class.
- Commit messages follow the repo's sentence-case imperative style ("Add …", "Route …") and end with the trailer `Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>`.
- Tests live under `test/resteze/`, use `Minitest::Spec`, `describe`/`it`, and WebMock's `stub_request` / `assert_requested`. Fixture modules shared across files go in `test/test_helper.rb`; fixtures used by one file are defined at the top of that file (see `test/resteze/save_test.rb`).

## Review Focus

1. **Member action called on a resource with a blank id** must raise the module's `InvalidRequestError`, never send a collection-path request. Pinned in Task 5.
2. **A path segment with reserved URL characters, or containing `/`** must escape each part and keep the slash as a separator (`"export/ids"` → `/users/export/ids`, `"a|b"` → `/widgets/a%7Cb`). Pinned in Task 1.
3. **A consumer param whose key equals the id param** must win over the merged id, not be overwritten. Pinned in Task 5.
4. **Module-level `action` / `action_defaults` called after resource classes are loaded** (Rails initializer ordering) must change what those classes resolve. Pinned in Task 4.
5. **A 204 or non-JSON response to a custom action** must yield an empty `Result` with `http_response` set, never raise from `Hashie::Mash`. Pinned in Task 2.

---

### Task 1: `Resteze::Action` value object and `default_id_param` hook

**Files:**
- Create: `lib/resteze/action.rb`
- Modify: `lib/resteze.rb` (add `require "resteze/action"` after `require "resteze/util"`; add `default_id_param` to `ClassMethods`)
- Test: `test/resteze/action_test.rb`, `test/resteze_test.rb`

**Interfaces:**
- Consumes: `klass.resource_path(id = nil)`, `klass.resource_slug`, `klass.api_module` (existing `ApiResource` class methods).
- Produces:
  - `Resteze::Action::OPTIONS = %i[method on path id id_param returns as]` (frozen).
  - `Resteze::Action::RESERVED = %i[retrieve list create update]` (frozen).
  - `Resteze::Action::BUILT_IN` frozen hash: `retrieve: { method: :get, on: :member, path: nil, id: :path }`, `list: { method: :get, on: :collection, path: nil }`, `create: { method: :post, on: :collection, path: nil }`, `update: { method: :put, on: :member, path: nil, id: :path }`.
  - `Resteze::Action.new(name, owner, options = {})` where `owner` is the resource class.
  - Readers: `name`, `owner`, `on`, `path`, `id`, `returns`, `as`; `http_method` (raises `ArgumentError` naming the action and owner when unset); `id_param`; `generated_name` (`as || name`); `reserved?`, `member?`, `collection?`; `path_segments` (Array of escaped strings); `path_for(id = nil)`; `to_h` (keys `:name, :method, :on, :path, :id, :id_param, :returns, :as`; `:method` is the raw value with nil allowed, `:id_param` and `:as` are the resolved `id_param` and `generated_name`).
  - `Resteze::ClassMethods#default_id_param(klass)` → `:"#{klass.resource_slug.singularize}_id"`.

- [ ] **Step 1: Write the failing tests**

`test/resteze/action_test.rb`:

```ruby
require "test_helper"

module Resteze
  class ActionTest < Minitest::Spec
    # rubocop:disable Style/ClassAndModuleChildren
    class AcmeApi::Keyed < AcmeApi::ApiResource
      def self.id_param
        :keyed_key
      end
    end
    # rubocop:enable Style/ClassAndModuleChildren

    def action(name, owner = AcmeApi::Widget, **options)
      Resteze::Action.new(name, owner, options)
    end

    describe "defaults" do
      it "defaults on to :collection and path to the name for custom actions" do
        a = action(:ping, method: :get)

        assert_equal :collection, a.on
        assert_equal "ping", a.path
        assert_predicate a, :collection?
        refute_predicate a, :reserved?
      end

      it "defaults path to nil for reserved names" do
        assert_nil action(:retrieve, **Action::BUILT_IN[:retrieve]).path
        assert_predicate action(:retrieve, **Action::BUILT_IN[:retrieve]), :reserved?
      end

      it "defaults id to :path for member actions and discards id options on collection actions" do
        assert_equal :path, action(:dup, method: :post, on: :member).id
        assert_nil action(:ping, method: :get, id: :param, id_param: :x).id
      end

      it "uses as for generated_name when given" do
        assert_equal :deliver, action(:send, method: :post, as: :deliver).generated_name
        assert_equal :ping, action(:ping, method: :get).generated_name
      end
    end

    describe "#http_method" do
      it "returns the method" do
        assert_equal :post, action(:ping, method: :post).http_method
      end

      it "raises when no method is set" do
        error = assert_raises(ArgumentError) { action(:ping).http_method }

        assert_match(/ping/, error.message)
        assert_match(/Widget/, error.message)
      end

      it "still reports the raw value through to_h" do
        assert_nil action(:ping).to_h[:method]
      end
    end

    describe "#id_param" do
      it "defaults to the singular slug plus _id" do
        assert_equal :widget_id, action(:dup, method: :post, on: :member).id_param
        assert_equal :gizmo_device_id, action(:dup, AcmeApi::GizmoDevice, method: :post, on: :member).id_param
      end

      it "prefers the option, then the owner's id_param" do
        assert_equal :wid, action(:dup, method: :post, on: :member, id_param: :wid).id_param
        assert_equal :keyed_key, action(:dup, AcmeApi::Keyed, method: :post, on: :member).id_param
      end
    end

    describe "#path_for" do
      it "builds the REST retrieve path" do
        assert_equal "/widgets/abc", action(:retrieve, **Action::BUILT_IN[:retrieve]).path_for("abc")
      end

      it "puts the segment after the id for :path member actions" do
        assert_equal "/widgets/abc/duplicate", action(:duplicate, method: :post, on: :member).path_for("abc")
      end

      it "omits the id for :param member actions" do
        a = action(:retrieve, method: :get, on: :member, path: "details", id: :param)

        assert_equal "/widgets/details", a.path_for("abc")
      end

      it "appends a collection segment" do
        assert_equal "/widgets/list", action(:list, method: :get, path: "list").path_for
        assert_equal "/widgets", action(:list, method: :get, path: nil).path_for
      end

      it "splits segments on / and escapes each part" do
        assert_equal "/widgets/export/ids", action(:export_ids, method: :post, path: "export/ids").path_for
        assert_equal "/widgets/a%7Cb", action(:odd, method: :get, path: "a|b").path_for
        assert_equal %w[export ids], action(:export_ids, method: :post, path: "export/ids").path_segments
      end

      it "honors a resource_path override" do
        assert_equal "/gizmos/list", action(:list, AcmeApi::GizmoDevice, method: :get, path: "list").path_for
      end
    end

    describe "#to_h" do
      it "includes every option plus name" do
        expected = { name: :dup, method: :post, on: :member, path: "dup", id: :param, id_param: :widget_id,
                     returns: :self, as: :dup }

        assert_equal expected, action(:dup, method: :post, on: :member, id: :param, returns: :self).to_h
      end
    end
  end
end
```

Add to `test/resteze_test.rb`, after the `.default_api_key` describe at the top level:

```ruby
  describe ".default_id_param" do
    it "should return the singular slug plus _id as a symbol" do
      assert_equal :widget_id, AcmeApi.default_id_param(AcmeApi::Widget)
      assert_equal :gizmo_device_id, AcmeApi.default_id_param(AcmeApi::GizmoDevice)
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/resteze/action_test.rb`
Expected: FAIL with `uninitialized constant Resteze::Action`

- [ ] **Step 3: Implement `Resteze::Action` in `lib/resteze/action.rb` and `default_id_param` in `lib/resteze.rb`**

`initialize(name, owner, options = {})`: symbolize `name`; store `@options = options.slice(*OPTIONS)`; for collection actions drop `:id` and `:id_param`. `on` = `options[:on] || BUILT_IN.dig(name, :on) || :collection`. `path` = `options.fetch(:path) { reserved? ? nil : name.to_s }`. `id` = member? ? `options.fetch(:id, :path)` : nil.

`id_param`: `@options[:id_param] || (owner.id_param if owner.respond_to?(:id_param)) || owner.api_module.default_id_param(owner)`.

`path_segments`: `path.to_s.split("/").reject(&:blank?).map { |part| CGI.escape(part) }`.

`path_for(id = nil)`: `base = member? && self.id == :path ? owner.resource_path(id) : owner.resource_path`; return `[base, *path_segments].join("/").squeeze("/")`.

`http_method`: `@options[:method] or raise ArgumentError, "Action :#{name} on #{owner} has no HTTP method; declare it with method: on the resource or at module level"`.

`default_id_param(klass)` in `Resteze::ClassMethods`: `:"#{klass.resource_slug.singularize}_id"`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -Ilib:test test/resteze/action_test.rb && bundle exec ruby -Ilib:test test/resteze_test.rb`
Expected: all PASS

- [ ] **Step 5: Run the full suite and RuboCop**

Run: `bundle exec rake`
Expected: 0 failures, 0 errors, no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/resteze/action.rb lib/resteze.rb test/resteze/action_test.rb test/resteze_test.rb
git commit -m "Add Resteze::Action value object for routed resource actions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 2: `Resteze::Result` and the namespaced `Result` constant

**Files:**
- Create: `lib/resteze/result.rb`
- Modify: `lib/resteze.rb` (require after `resteze/response`; `const_set :Result, Class.new(Resteze::Result)` in the `included` block right after `:Response`)
- Test: `test/resteze/result_test.rb`, `test/resteze_test.rb`

**Interfaces:**
- Consumes: `Resteze::Response` (`data`, `http_status`), `Resteze::ApiModule`.
- Produces: `Resteze::Result < Hashie::Mash` with `include Resteze::ApiModule`, `disable_warnings`, `attr_reader :http_response`, and `Resteze::Result.from_response(response)` returning an instance whose Mash contents are `response.data` when that is a Hash and empty otherwise. `MyApi::Result` exists for every including module.

- [ ] **Step 1: Write the failing tests**

`test/resteze/result_test.rb`:

```ruby
require "test_helper"

module Resteze
  class ResultTest < Minitest::Spec
    def response_with(data, status: 200)
      AcmeApi::Response.new.tap do |r|
        r.data = data
        r.http_status = status
      end
    end

    describe ".from_response" do
      it "exposes hash data with dot and key access" do
        result = AcmeApi::Result.from_response(response_with({ message: "success", counts: { events: 2 } }))

        assert_equal "success", result.message
        assert_equal "success", result[:message]
        assert_equal 2, result.counts.events
      end

      it "keeps the response" do
        response = response_with({ message: "success" })
        result = AcmeApi::Result.from_response(response)

        assert_same response, result.http_response
        assert_equal 200, result.http_response.http_status
      end

      it "is empty for a non-hash body and never raises" do
        empty = AcmeApi::Result.from_response(response_with("", status: 204))
        array = AcmeApi::Result.from_response(response_with([{ id: 1 }]))

        assert_empty empty
        assert_equal "", empty.http_response.data
        assert_empty array
        assert_equal [{ id: 1 }], array.http_response.data
      end
    end

    it "is namespaced per API module" do
      assert_operator AcmeApi::Result, :<, Resteze::Result
      assert_equal AcmeApi, AcmeApi::Result.api_module
    end

    it "disables Hashie key collision warnings" do
      assert_predicate AcmeApi::Result, :disable_warnings?
    end
  end
end
```

In `test/resteze_test.rb`, add `Result` to the `expected_constants` list (after `Response`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/resteze/result_test.rb`
Expected: FAIL with `uninitialized constant AcmeApi::Result`

- [ ] **Step 3: Implement `Resteze::Result` in `lib/resteze/result.rb` and wire the constant in `lib/resteze.rb`**

`from_response(response)`: `data = response.data; new(data.is_a?(Hash) ? data : {}).tap { |r| r.instance_variable_set(:@http_response, response) }`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -Ilib:test test/resteze/result_test.rb && bundle exec ruby -Ilib:test test/resteze_test.rb`
Expected: all PASS

- [ ] **Step 5: Run the full suite and RuboCop**

Run: `bundle exec rake`
Expected: 0 failures, no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/resteze/result.rb lib/resteze.rb test/resteze/result_test.rb test/resteze_test.rb
git commit -m "Add Resteze::Result as the loose return object for custom actions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 3: Module-level `action` and `action_defaults`

**Files:**
- Modify: `lib/resteze.rb` (`Resteze::ClassMethods`)
- Test: `test/resteze_test.rb`

**Interfaces:**
- Consumes: `Resteze::Action::OPTIONS`.
- Produces on every including module (and on `Resteze` itself, harmlessly):
  - `action(name, **options)` → validates `options.keys ⊆ Action::OPTIONS` (else `ArgumentError`), stores `options` under `name.to_sym` in `action_declarations`, returns nil.
  - `action_declarations` → `Hash` of name → options, own to the module, `{}` by default.
  - `action_defaults(**options)` → with options: validates keys ⊆ `%i[method id id_param]` (else `ArgumentError`), merges into the stored defaults; with no options: returns the stored defaults Hash, `{}` by default.

- [ ] **Step 1: Write the failing tests**

Add to `test/resteze_test.rb` inside the top-level class, after `.default_id_param`:

```ruby
  describe "module-level actions" do
    class Verbish
      include Resteze
    end

    it "stores action declarations by name" do
      Verbish.action :retrieve, path: "details"
      Verbish.action "track", method: :post

      assert_equal({ path: "details" }, Verbish.action_declarations[:retrieve])
      assert_equal({ method: :post }, Verbish.action_declarations[:track])
      assert_empty AcmeApi.action_declarations
    end

    it "stores and returns action defaults" do
      assert_empty Verbish.action_defaults
      Verbish.action_defaults id: :param
      Verbish.action_defaults method: :post

      assert_equal({ id: :param, method: :post }, Verbish.action_defaults)
    end

    it "rejects unknown options" do
      assert_raises(ArgumentError) { Verbish.action :retrieve, verb: :get }
      assert_raises(ArgumentError) { Verbish.action_defaults path: "x" }
      assert_raises(ArgumentError) { Verbish.action_defaults on: :member }
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/resteze_test.rb`
Expected: FAIL with `undefined method 'action' for class Verbish`

- [ ] **Step 3: Implement the three methods in `Resteze::ClassMethods`**

Store in `@action_declarations` and `@action_defaults` instance variables on the module. `action_defaults` is dual-use: `options.empty?` returns the hash, otherwise validates and `merge!`s.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -Ilib:test test/resteze_test.rb`
Expected: PASS

- [ ] **Step 5: Run the full suite and RuboCop**

Run: `bundle exec rake`
Expected: 0 failures, no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/resteze.rb test/resteze_test.rb
git commit -m "Add module-level action and action_defaults declarations

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 4: `Resteze::Actions` registry with lazy resolution

**Files:**
- Create: `lib/resteze/actions.rb`
- Modify: `lib/resteze.rb` (require `resteze/actions` before `resteze/api_resource`), `lib/resteze/api_resource.rb` (add `include Resteze::Actions` next to `include Resteze::Request`), `test/test_helper.rb` (add the `VerbApi` fixture module)
- Test: `test/resteze/actions_test.rb`

**Interfaces:**
- Consumes: `Resteze::Action` (Task 1), module `action_declarations` / `action_defaults` (Task 3), `api_module::List`.
- Produces, as `ApiResource` class methods:
  - `action(name, **options)` → declaration-time validation (below), stores options in `declared_actions[name.to_sym]`, returns nil. Method generation is added in Task 5.
  - `declared_actions` → own-class Hash, `{}` by default, not inherited.
  - `actions` → frozen Hash of name → `Resteze::Action`, rebuilt on every call (no memoization). Names are `Action::RESERVED` plus every name declared on this class or any ancestor class that responds to `declared_actions`. Module-level custom declarations do not add names.
  - `resolve_action(name)` (private) → merges, lowest priority first: `Action::BUILT_IN.fetch(name, {})`, `api_module.action_defaults`, `api_module.action_declarations.fetch(name, {})`, then each ancestor class's `declared_actions.fetch(name, {})` from farthest to nearest, then this class's own. Returns `Action.new(name, self, merged)`.

Declaration-time validation in `action`, each raising `ArgumentError`: unknown option keys; `on:` given for a reserved name; `id:` or `id_param:` given when the declaration-time `on` is `:collection` (declaration-time `on` = `options[:on] || api_module.action_declarations.dig(name, :on) || BUILT_IN.dig(name, :on) || :collection`); `returns: :list` when `ancestors` does not include `Resteze::List`.

- [ ] **Step 1: Add the `VerbApi` fixture to `test/test_helper.rb`**

After the `AcmeApi` module:

```ruby
module VerbApi
  include Resteze

  action_defaults id: :param

  action :retrieve, path: "details"
  action :list,     path: "list"
  action :create,   path: "create"
  action :update,   path: "update", method: :post
  action :export,   method: :post

  def self.default_list_key(klass)
    klass.resource_slug.to_sym
  end

  class Campaign < ApiResource
    include List

    property :id
    property :name

    action :data_series, method: :get
    action :duplicate,   method: :post, on: :member
  end

  class SpecialCampaign < Campaign
    action :duplicate, path: "clone"
  end

  class ContentBlock < ApiResource
    include List
    include Save

    property :id
    property :content

    action :retrieve, path: "info"
  end

  class User < ApiResource
    property :external_id

    action :track,      method: :post
    action :export
    action :export_ids, method: :post, path: "export/ids"
  end
end

VerbApi.configure do |config|
  config.api_base = "http://verb.example.com/"
  config.logger = Logger.new(nil)
end
```

Also add a `verb_url(path)` helper next to `api_url` in the `Minitest::Spec` reopening: `VerbApi::Client.api_url(VerbApi::ApiResource.api_path(path))`.

- [ ] **Step 2: Write the failing tests**

`test/resteze/actions_test.rb`:

Fixtures are real named classes. `ApiModule.api_module` constantizes every name in
the ancestry chain, so an anonymous class with a faked `name` does not resolve.

```ruby
require "test_helper"

module Resteze
  class ActionsTest < Minitest::Spec
    # rubocop:disable Style/ClassAndModuleChildren
    class AcmeApi::Thing < AcmeApi::ApiResource
      action :ping
    end

    class AcmeApi::Invalid < AcmeApi::ApiResource; end
    # rubocop:enable Style/ClassAndModuleChildren

    module LateApi
      include Resteze

      class Thing < ApiResource; end
    end

    describe ".actions" do
      it "exposes the four built-ins with REST defaults when nothing is declared" do
        actions = AcmeApi::Widget.actions

        assert_equal %i[create list retrieve update], actions.keys.sort
        assert_predicate actions, :frozen?
        assert_equal :get, actions[:retrieve].http_method
        assert_equal :path, actions[:retrieve].id
        assert_equal "/widgets/1", actions[:retrieve].path_for("1")
        assert_equal "/widgets", actions[:list].path_for
      end

      it "applies module defaults and module declarations" do
        actions = VerbApi::Campaign.actions

        assert_equal :param, actions[:retrieve].id
        assert_equal "/campaigns/details", actions[:retrieve].path_for("abc")
        assert_equal "/campaigns/list", actions[:list].path_for
        assert_equal :post, actions[:update].http_method
        assert_equal "/campaigns/update", actions[:update].path_for("abc")
      end

      it "lets a resource override the module" do
        assert_equal "/content_blocks/info", VerbApi::ContentBlock.actions[:retrieve].path_for("x")
      end

      it "lets a module declaration supply a custom action's method" do
        assert_equal :post, VerbApi::User.actions[:export].http_method
        refute VerbApi::Campaign.actions.key?(:export), "module-level custom actions are not visible unless declared"
      end

      it "inherits and overrides per option without touching the parent" do
        assert_equal :post, VerbApi::SpecialCampaign.actions[:duplicate].http_method
        assert_equal "/campaigns/clone", VerbApi::SpecialCampaign.actions[:duplicate].path_for("1")
        assert_equal "/campaigns/duplicate", VerbApi::Campaign.actions[:duplicate].path_for("1")
        assert_empty VerbApi::SpecialCampaign.declared_actions.except(:duplicate)
      end

      it "resolves lazily so later module declarations take effect" do
        assert_equal "/things/1", LateApi::Thing.actions[:retrieve].path_for("1")
        LateApi.action :retrieve, path: "show"
        LateApi.action_defaults id: :param

        assert_equal "/things/show", LateApi::Thing.actions[:retrieve].path_for("1")
      end

      it "raises on first use of a custom action with no method" do
        error = assert_raises(ArgumentError) { AcmeApi::Thing.actions[:ping].http_method }

        assert_match(/ping/, error.message)
        assert_match(/Thing/, error.message)
      end
    end

    describe ".action validation" do
      subject { AcmeApi::Invalid }

      it "rejects unknown options" do
        assert_raises(ArgumentError) { subject.action :ping, verb: :get }
      end

      it "rejects on: for reserved names" do
        assert_raises(ArgumentError) { subject.action :retrieve, on: :collection }
      end

      it "rejects id options on collection actions" do
        assert_raises(ArgumentError) { subject.action :ping, method: :get, id: :param }
        assert_raises(ArgumentError) { subject.action :ping, method: :get, id_param: :x }
      end

      it "rejects returns: :list without List" do
        assert_raises(ArgumentError) { subject.action :ping, method: :get, returns: :list }
      end

      it "stores nothing when validation fails" do
        assert_empty subject.declared_actions
      end
    end
  end
end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/resteze/actions_test.rb`
Expected: FAIL with `undefined method 'action' for class VerbApi::Campaign` (raised while loading the helper)

- [ ] **Step 4: Implement `Resteze::Actions` in `lib/resteze/actions.rb` and include it from `Resteze::ApiResource`**

`Resteze::Actions` is an `ActiveSupport::Concern` with a `ClassMethods` module. Ancestor walk: `ancestors.select { |a| a.is_a?(Class) && a.respond_to?(:declared_actions) }` is nearest-first; iterate it with `reverse_each` when merging.

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec ruby -Ilib:test test/resteze/actions_test.rb`
Expected: PASS

- [ ] **Step 6: Run the full suite and RuboCop**

Run: `bundle exec rake`
Expected: 0 failures, no offenses

- [ ] **Step 7: Commit**

```bash
git add lib/resteze/actions.rb lib/resteze.rb lib/resteze/api_resource.rb test/test_helper.rb test/resteze/actions_test.rb
git commit -m "Add the Actions registry with lazy lookup-chain resolution

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 5: Method generation and invocation for custom actions

**Files:**
- Modify: `lib/resteze/actions.rb`
- Test: `test/resteze/actions_test.rb`

**Interfaces:**
- Consumes: Task 4 registry, `request(method, path, params:, headers:)`, `api_module::InvalidRequestError`, `api_module::Result.from_response`.
- Produces:
  - `action(name, **options)` now also generates methods for non-reserved names. Generated name = `options[:as] || name`. Collection: singleton method `Klass.<as>(**params)`. Member: instance method `#<as>(**params)` and singleton `Klass.<as>(id, **params)` which is `new(id).public_send(as, **params)`. Collision check before defining: for the singleton form `respond_to?(as, true)` on the class; for the instance form `method_defined?(as) || private_method_defined?(as)`. On collision raise `ArgumentError` whose message names the method and contains the text `as:`.
  - `invoke_action(name, params = {}, id: nil)` public class method: `action = actions.fetch(name)`; for member actions raise `api_module::InvalidRequestError.new("Could not determine which PATH to request: #{self} instance has invalid ID: #{id.inspect}", "id")` when `id.blank?`; `params = action_params(name, params)`; when `action.member? && action.id == :param`, `params = { action.id_param => id }.merge(params)`; `response = request(action.http_method, action.path_for(id), params:, headers: action_headers(name, params))`; return `build_action_result(action, response)`.
  - `action_params(_name, params)` → `params` (public, overridable). `action_headers(_name, _params)` → `{}` (public, overridable).
  - `build_action_result(action, response)` (private) → in this task always `api_module::Result.from_response(response)`; Task 6 adds the `returns:` branches.

- [ ] **Step 1: Write the failing tests**

Add these named fixtures to the top of `test/resteze/actions_test.rb`, inside the
existing `rubocop:disable Style/ClassAndModuleChildren` block:

```ruby
    class AcmeApi::Doohickey < AcmeApi::ApiResource
      action :activate, method: :post, on: :member
    end

    class AcmeApi::Hooked < AcmeApi::ApiResource
      action :ping, method: :post

      def self.action_params(name, params) = params.merge(source: name.to_s)
      def self.action_headers(_name, _params) = { "X-Action" => "yes" }
    end

    class AcmeApi::Clash < AcmeApi::ApiResource
      property :status
    end
```

Then append inside the class:

```ruby
    describe "generated collection actions" do
      it "posts params as a JSON body and returns a Result" do
        stub_request(:post, verb_url("/users/track")).to_return(body: { message: "success" }.to_json)
        result = VerbApi::User.track(events: [{ name: "x" }])

        assert_requested :post, verb_url("/users/track"), body: { events: [{ name: "x" }] }.to_json
        assert_kind_of VerbApi::Result, result
        assert_equal "success", result.message
      end

      it "sends GET params as a query string" do
        stub_request(:get, verb_url("/campaigns/data_series")).with(query: { length: "7" }).to_return(body: "{}")
        VerbApi::Campaign.data_series(length: 7)

        assert_requested :get, verb_url("/campaigns/data_series"), query: { length: "7" }
      end

      it "routes a slashed path" do
        stub_request(:post, verb_url("/users/export/ids")).to_return(body: "{}")
        VerbApi::User.export_ids(external_ids: ["1"])

        assert_requested :post, verb_url("/users/export/ids")
      end
    end

    describe "generated member actions" do
      it "merges the id param into the body for :param placement" do
        stub_request(:post, verb_url("/campaigns/duplicate")).to_return(body: "{}")
        VerbApi::Campaign.new("abc").duplicate(name: "copy")

        assert_requested :post, verb_url("/campaigns/duplicate"), body: { campaign_id: "abc", name: "copy" }.to_json
      end

      it "offers a class form that takes the id first" do
        stub_request(:post, verb_url("/campaigns/duplicate")).to_return(body: "{}")
        VerbApi::Campaign.duplicate("abc", name: "copy")

        assert_requested :post, verb_url("/campaigns/duplicate"), body: { campaign_id: "abc", name: "copy" }.to_json
      end

      it "lets a consumer param override the id param" do
        stub_request(:post, verb_url("/campaigns/duplicate")).to_return(body: "{}")
        VerbApi::Campaign.new("abc").duplicate(campaign_id: "zzz")

        assert_requested :post, verb_url("/campaigns/duplicate"), body: { campaign_id: "zzz" }.to_json
      end

      it "puts the id in the path for :path placement" do
        stub_request(:post, api_url("/doohickeys/1/activate")).to_return(body: "{}")
        AcmeApi::Doohickey.new("1").activate

        assert_requested :post, api_url("/doohickeys/1/activate"), body: "{}"
      end

      it "raises InvalidRequestError for a blank id" do
        assert_raises(VerbApi::InvalidRequestError) { VerbApi::Campaign.new.duplicate(name: "copy") }
        assert_raises(VerbApi::InvalidRequestError) { VerbApi::Campaign.duplicate("", name: "copy") }
      end
    end

    describe "hooks" do
      it "passes params through action_params and headers through action_headers" do
        stub_request(:post, api_url("/hookeds/ping")).to_return(body: "{}")
        AcmeApi::Hooked.ping(a: 1)

        assert_requested :post, api_url("/hookeds/ping"), body: { a: 1, source: "ping" }.to_json,
                                                          headers: { "X-Action" => "yes" }
      end

      it "defaults to pass-through and empty headers" do
        assert_equal({ a: 1 }, AcmeApi::Widget.action_params(:x, { a: 1 }))
        assert_empty AcmeApi::Widget.action_headers(:x, {})
      end
    end

    describe "method-name collisions" do
      subject { AcmeApi::Clash }

      it "rejects a collection action that collides with a class method" do
        error = assert_raises(ArgumentError) { subject.action :send, method: :post }

        assert_match(/send/, error.message)
        assert_match(/as:/, error.message)
      end

      it "rejects a member action that collides with a Hash method" do
        assert_raises(ArgumentError) { subject.action :delete, method: :post, on: :member }
      end

      it "rejects a member action that collides with a property accessor" do
        assert_raises(ArgumentError) { subject.action :status, method: :get, on: :member }
      end

      it "accepts as: to pick a different method name" do
        subject.action :send, method: :post, as: :deliver

        assert_respond_to subject, :deliver
      end

      it "never generates for reserved names" do
        subject.action :create, path: "create"

        refute_respond_to subject, :create
      end
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/resteze/actions_test.rb`
Expected: FAIL with `undefined method 'track' for class VerbApi::User`

- [ ] **Step 3: Implement generation and `invoke_action` in `lib/resteze/actions.rb`**

Generation happens inside `action` after validation and storage, only when `!Action::RESERVED.include?(name)`. Use `define_singleton_method` and `define_method` with `**params` blocks that call `invoke_action`. Keep `action` under the 15-line RuboCop limit by splitting into `validate_action_options!`, `check_action_collision!` and `define_action_methods`.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `bundle exec ruby -Ilib:test test/resteze/actions_test.rb`
Expected: PASS

- [ ] **Step 5: Run the full suite and RuboCop**

Run: `bundle exec rake`
Expected: 0 failures, no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/resteze/actions.rb test/resteze/actions_test.rb
git commit -m "Generate and invoke custom collection and member actions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 6: `returns:` handling

**Files:**
- Modify: `lib/resteze/actions.rb` (`build_action_result`), `test/test_helper.rb` (add `VerbApi::TrackResult` and `returns:` declarations)
- Test: `test/resteze/actions_test.rb`

**Interfaces:**
- Consumes: `construct_from(payload)`, `util.convert_to_object(data, klass)`, `construct_list_from(payload)`.
- Produces: `build_action_result(action, response)` returning, by `action.returns`: `nil` → `api_module::Result.from_response(response)`; `:self` → `convert_action_data(response.data, self)`; `:list` → `construct_list_from(response.data)`; a `Class` → `convert_action_data(response.data, klass)`. `convert_action_data(data, klass)` (private): `Hash` → `klass.construct_from(data)`; `Array` → `util.convert_to_object(data, klass)`; anything else → `data` unchanged.

- [ ] **Step 1: Extend the fixtures in `test/test_helper.rb`**

Inside `VerbApi`, before `Campaign`:

```ruby
  class TrackResult < Object
    property :message
    property :events_processed
  end
```

Add to `VerbApi::Campaign`: `action :featured, method: :get, returns: :self` and `action :search, method: :get, returns: :list`. Change `duplicate` to `action :duplicate, method: :post, on: :member, returns: :self`. Add to `VerbApi::User`: `action :track_typed, method: :post, path: "track", returns: TrackResult`.

Add a second module after `VerbApi` for the `object_key` case:

```ruby
module WrapApi
  include Resteze

  def self.default_object_key(_klass)
    :item
  end

  class Thing < ApiResource
    property :id

    action :featured, method: :get, returns: :self
  end
end

WrapApi.configure do |config|
  config.api_base = "http://wrap.example.com/"
  config.logger = Logger.new(nil)
end
```

- [ ] **Step 2: Write the failing tests**

Append to `test/resteze/actions_test.rb`:

```ruby
    describe "returns:" do
      it "builds one resource from a hash with returns: :self" do
        stub_request(:get, verb_url("/campaigns/featured")).to_return(body: { id: "1", name: "Hot" }.to_json)
        campaign = VerbApi::Campaign.featured

        assert_kind_of VerbApi::Campaign, campaign
        assert_equal "Hot", campaign.name
      end

      it "builds an array of resources from an array with returns: :self" do
        stub_request(:get, verb_url("/campaigns/featured")).to_return(body: [{ id: "1" }, { id: "2" }].to_json)
        campaigns = VerbApi::Campaign.featured

        assert_equal %w[1 2], campaigns.map(&:id)
        assert_kind_of VerbApi::Campaign, campaigns.first
      end

      it "unwraps object_key for a hash and wraps items for an array" do
        stub_request(:get, "http://wrap.example.com/things/featured")
          .to_return({ body: { item: { id: "1" } }.to_json }, { body: [{ id: "2" }, { id: "3" }].to_json })

        assert_equal "1", WrapApi::Thing.featured.id
        assert_equal %w[2 3], WrapApi::Thing.featured.map(&:id)
      end

      it "returns a new instance from a member action and leaves the receiver alone" do
        stub_request(:post, verb_url("/campaigns/duplicate")).to_return(body: { id: "def", name: "copy" }.to_json)
        original = VerbApi::Campaign.new("abc", values: { name: "orig" })
        copy = original.duplicate(name: "copy")

        assert_equal "def", copy.id
        assert_equal "abc", original.id
        assert_equal "orig", original.name
        refute_same original, copy
      end

      it "builds a ListObject with returns: :list using the resource's list_key" do
        stub_request(:get, verb_url("/campaigns/search")).to_return(body: { campaigns: [{}, {}], page: 0 }.to_json)
        list = VerbApi::Campaign.search(q: "x")

        assert_kind_of VerbApi::ListObject, list
        assert_equal 2, list.length
        assert_equal({ page: 0 }, list.metadata)
      end

      it "builds the named Object subclass" do
        stub_request(:post, verb_url("/users/track")).to_return(body: { message: "success", events_processed: 2 }.to_json)
        result = VerbApi::User.track_typed(events: [])

        assert_kind_of VerbApi::TrackResult, result
        assert_equal 2, result.events_processed
      end

      it "returns non-hash, non-array data unchanged for returns: :self" do
        stub_request(:get, verb_url("/campaigns/featured")).to_return(status: 204, body: "")

        assert_equal "", VerbApi::Campaign.featured
      end
    end
```

- [ ] **Step 3: Run the tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/resteze/actions_test.rb`
Expected: FAIL on "builds one resource from a hash" with `expected VerbApi::Campaign, got VerbApi::Result`

- [ ] **Step 4: Implement the `returns:` branches of `build_action_result` and `convert_action_data` in `lib/resteze/actions.rb`**

- [ ] **Step 5: Run the tests to verify they pass**

Run: `bundle exec ruby -Ilib:test test/resteze/actions_test.rb`
Expected: PASS

- [ ] **Step 6: Run the full suite and RuboCop**

Run: `bundle exec rake`
Expected: 0 failures, no offenses

- [ ] **Step 7: Commit**

```bash
git add lib/resteze/actions.rb test/test_helper.rb test/resteze/actions_test.rb
git commit -m "Support returns: on custom actions

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 7: Route the built-in actions through the registry

**Files:**
- Modify: `lib/resteze/api_resource.rb`, `lib/resteze/list.rb`, `lib/resteze/save.rb`
- Test: `test/resteze/api_resource_test.rb`, `test/resteze/list_test.rb`, `test/resteze/save_test.rb`

**Interfaces:**
- Consumes: `actions.fetch(name)` → `Resteze::Action` with `http_method`, `path_for(id)`, `id`, `id_param`.
- Produces:
  - `ApiResource#retrieve_resource_path` (new, public): raises the existing `InvalidRequestError` when `id.blank?`, else `self.class.actions.fetch(:retrieve).path_for(id)`. `refresh` calls it instead of `resource_path`. `ApiResource#resource_path` is unchanged.
  - `ApiResource#retrieve_method` → `self.class.actions.fetch(:retrieve).http_method`.
  - `ApiResource#retrieve_params` → `@retrieve_params || {}` merged under `{ id_param => id }` only when the retrieve action is `id: :param` (consumer values win).
  - `List.list_resource_path(_params = {})` → `actions.fetch(:list).path_for`. `List.list_method` → `actions.fetch(:list).http_method`.
  - `Save#save_method` → `self.class.actions.fetch(persisted? ? :update : :create).http_method`.
  - `Save#save_resource_path` → `persisted? ? self.class.actions.fetch(:update).path_for(id) : self.class.actions.fetch(:create).path_for`.
  - `Save#save_params` (new, public): `as_save_json`, merged under `{ id_param.to_s => id }` when persisted and the update action is `id: :param`. `save` sends `save_params` instead of `as_save_json`.

- [ ] **Step 1: Write the failing tests**

Append to `test/resteze/api_resource_test.rb` inside the class:

```ruby
    describe "#retrieve_resource_path" do
      it "matches resource_path for REST defaults" do
        assert_equal "/toy-service/v3/yo_yos/1", AcmeApi::YoYoA.new("1").retrieve_resource_path
      end

      it "uses the routed retrieve action" do
        assert_equal "/campaigns/details", VerbApi::Campaign.new("abc").retrieve_resource_path
        assert_equal "/content_blocks/info", VerbApi::ContentBlock.new("x").retrieve_resource_path
      end

      it "rejects a blank id" do
        assert_raises(VerbApi::InvalidRequestError) { VerbApi::Campaign.new.retrieve_resource_path }
      end
    end

    describe "routed retrieve" do
      it "leaves retrieve_params alone for :path placement" do
        assert_empty ::AcmeApi::Widget.new("1").retrieve_params
      end

      it "merges the id param for :param placement, consumer values winning" do
        assert_equal({ campaign_id: "abc" }, VerbApi::Campaign.new("abc").retrieve_params)
        assert_equal({ campaign_id: "zzz" }, VerbApi::Campaign.new({ id: "abc", campaign_id: "zzz" }).retrieve_params)
      end

      it "requests the verb-style path with the id as a query param" do
        stub_request(:get, verb_url("/campaigns/details")).with(query: { campaign_id: "abc" })
                                                           .to_return(body: { id: "abc", name: "Hi" }.to_json)
        campaign = VerbApi::Campaign.retrieve("abc")

        assert_equal "Hi", campaign.name
        assert_requested :get, verb_url("/campaigns/details"), query: { campaign_id: "abc" }
      end

      it "keeps instance resource_path meaning the record path" do
        assert_equal "/campaigns/abc", VerbApi::Campaign.new("abc").resource_path
      end
    end
```

Append to `test/resteze/list_test.rb` inside the class:

```ruby
    describe "routed list" do
      it "uses the list action path and method" do
        assert_equal "/campaigns/list", VerbApi::Campaign.list_resource_path
        assert_equal :get, VerbApi::Campaign.list_method
      end

      it "builds the list from the resource's list_key" do
        stub_request(:get, verb_url("/campaigns/list")).with(query: { page: "0" })
                                                        .to_return(body: { campaigns: [{}, {}] }.to_json)

        assert_equal 2, VerbApi::Campaign.list(params: { page: 0 }).length
      end
    end
```

Append to `test/resteze/save_test.rb` inside the class:

```ruby
    describe "routed save" do
      it "uses the create and update actions" do
        assert_equal :post, VerbApi::ContentBlock.new.save_method
        assert_equal :post, VerbApi::ContentBlock.new("x").save_method
        assert_equal "/content_blocks/create", VerbApi::ContentBlock.new.save_resource_path
        assert_equal "/content_blocks/update", VerbApi::ContentBlock.new("x").save_resource_path
      end

      it "merges the id param into save_params only when persisted with :param placement" do
        assert_equal "x", VerbApi::ContentBlock.new("x").save_params["content_block_id"]
        refute VerbApi::ContentBlock.new.save_params.key?("content_block_id")
        refute subject.new(1).save_params.key?("toy_id")
      end

      it "posts the update with the id in the body" do
        stub_request(:post, verb_url("/content_blocks/update")).to_return(body: { id: "x", content: "new" }.to_json)
        block = VerbApi::ContentBlock.new("x", values: { content: "new" })
        block.save

        assert_requested :post, verb_url("/content_blocks/update"),
                         body: { "content_block_id" => "x", "id" => "x", "content" => "new" }.to_json
        assert_equal "new", block.content
      end
    end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `bundle exec ruby -Ilib:test test/resteze/api_resource_test.rb`
Expected: FAIL with `undefined method 'retrieve_resource_path'`

- [ ] **Step 3: Rework `api_resource.rb`, `list.rb` and `save.rb` per the Interfaces block**

The existing `resource_path`, `resource_path(id)`, `list_params`, `list_headers`, `as_save_json`, `save_headers` and `process_save_response` bodies do not change.

- [ ] **Step 4: Run the three test files to verify they pass**

Run: `bundle exec rake test TEST="test/resteze/{api_resource,list,save}_test.rb"`
Expected: PASS, including every pre-existing test in those files

- [ ] **Step 5: Run the full suite and RuboCop**

Run: `bundle exec rake`
Expected: 0 failures, no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/resteze/api_resource.rb lib/resteze/list.rb lib/resteze/save.rb test/resteze/api_resource_test.rb test/resteze/list_test.rb test/resteze/save_test.rb
git commit -m "Route retrieve, list and save through the actions registry

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 8: `has_action` testing helpers

**Files:**
- Modify: `lib/resteze/testing/minitest/object.rb`, `lib/resteze/testing/rspec/object.rb`
- Test: `test/resteze/testing/minitest/object_test.rb`

**Interfaces:**
- Consumes: `subject.actions`, `Resteze::Action` readers.
- Produces, in both helper modules: `has_action(name, **options)`. Asserts `subject.actions[name.to_sym]` exists. Then, for each key present in `options`: `method:` against `http_method`; `on:` against `on`; `id:` against `id`; `id_param:` against `id_param`; `returns:` against `returns`; `as:` against `generated_name`; `path:` against `path_for("ID")` for member actions and `path_for` for collection actions. Split the per-option checks into a private `assert_action_options(action, options)` to stay within RuboCop limits, mirroring the `has_property` / `assert_property_*` layout.

- [ ] **Step 1: Write the failing test**

`test/resteze/testing/minitest/object_test.rb`:

```ruby
require "test_helper"
require "resteze/testing/minitest"

module Resteze
  module Testing
    class MinitestObjectTest < Minitest::Spec
      include Resteze::Testing::Minitest::Object

      subject { VerbApi::Campaign }

      it "passes for a declared action" do
        has_action :data_series, method: :get, on: :collection, path: "/campaigns/data_series"
        has_action :duplicate, method: :post, on: :member, id: :param, id_param: :campaign_id,
                               path: "/campaigns/duplicate", returns: :self, as: :duplicate
        has_action :retrieve, path: "/campaigns/details"
      end

      it "reports a missing action" do
        error = assert_raises(Minitest::Assertion) { has_action :nope }

        assert_match(/nope/, error.message)
      end

      it "reports a wrong option" do
        assert_raises(Minitest::Assertion) { has_action :data_series, method: :post }
        assert_raises(Minitest::Assertion) { has_action :duplicate, path: "/campaigns/ID/duplicate" }
      end
    end
  end
end
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `bundle exec ruby -Ilib:test test/resteze/testing/minitest/object_test.rb`
Expected: FAIL with `undefined method 'has_action'`

- [ ] **Step 3: Implement `has_action` in the Minitest helper, then mirror it in the RSpec helper with `expect(...).to eq(...)`**

Keep the `# rubocop:disable Naming/PredicatePrefix` wrapper the file already uses for `has_property`.

- [ ] **Step 4: Run the test to verify it passes, and syntax-check the RSpec file**

Run: `bundle exec ruby -Ilib:test test/resteze/testing/minitest/object_test.rb && ruby -c lib/resteze/testing/rspec/object.rb`
Expected: PASS and `Syntax OK`

- [ ] **Step 5: Run the full suite and RuboCop**

Run: `bundle exec rake`
Expected: 0 failures, no offenses

- [ ] **Step 6: Commit**

```bash
git add lib/resteze/testing/minitest/object.rb lib/resteze/testing/rspec/object.rb test/resteze/testing/minitest/object_test.rb
git commit -m "Add has_action testing helper for Minitest and RSpec

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```

---

### Task 9: Documentation, changelog and version bump

**Files:**
- Create: `docs/ACTIONS.md`
- Modify: `docs/API.md` ("Custom Request Methods" section), `docs/ADVANCED_USAGE.md` ("Custom List Methods" section), `docs/TESTING.md` (helpers list), `README.md` (Usage), `CHANGELOG.md`, `CLAUDE.md` (Architecture), `lib/resteze/version.rb`
- Test: `test/resteze_test.rb` (existing version assertion)

**Interfaces:**
- Consumes: everything above.
- Produces: `Resteze::VERSION = "0.5.0"`; a `[0.5.0]` changelog entry; user-facing docs for the DSL.

- [ ] **Step 1: Write `docs/ACTIONS.md`**

Sections, in order, each with one runnable Ruby example using a Braze-shaped `MyApi`: Why actions; Declaring custom actions (option table copied from the spec, including `as:`); Collection vs member and where the id goes; Re-routing the built-ins on a resource; API-wide defaults with `action_defaults` and module-level `action`; Lookup order; Return values (`Result`, `:self`, `:list`, a class) including the `object_key` note and the 204 note; Hooks (`action_params`, `action_headers`, `retrieve_resource_path`, `list_resource_path`, `save_resource_path`, `save_params`, `id_param`); Introspection (`actions`, `actions.fetch`); Testing with `has_action`; The escape hatch (hand-rolled `request` call, shown once).

- [ ] **Step 2: Update the existing docs**

In `docs/API.md` "Custom Request Methods": replace the `activate!` and `search` examples with `action :activate, method: :post, on: :member` and `action :search, method: :get, returns: :self`, keep `update_with_version` as the hand-rolled example, and link to `docs/ACTIONS.md`. In `docs/ADVANCED_USAGE.md` "Custom List Methods": replace `featured` and `search` with `action … returns: :self` / `returns: :list`. In `docs/TESTING.md`: add `has_action` beside `has_property`. In `README.md` Usage: one short example of `action` on a resource and a link to `docs/ACTIONS.md`. In `CLAUDE.md` Architecture: add a short "Actions" subsection describing the registry, the lookup chain and the four reserved names, and list `action.rb`, `actions.rb`, `result.rb` where the request flow is described.

- [ ] **Step 3: Changelog and version**

Add to the top of `CHANGELOG.md`:

```markdown
## [0.5.0]

### Added

- `action` routing DSL on `ApiResource`: declare custom collection and member actions, re-route `retrieve`, `list`, `create` and `update`, and set API-wide defaults with module-level `action` / `action_defaults`.
- `Result`, a loose Mash returned by custom actions by default; `returns:` selects a resource, a list, or any `Object` subclass instead.
- `retrieve_resource_path`, `save_params` and `id_param` override points.
- `has_action` assertion helper for Minitest and RSpec.
```

Set `VERSION = "0.5.0"` in `lib/resteze/version.rb`.

- [ ] **Step 4: Verify**

Run: `bundle exec rake && grep -n '"0.5.0"' lib/resteze/version.rb && grep -c "action" docs/ACTIONS.md`
Expected: 0 failures, no offenses, the version line, and a non-zero count

- [ ] **Step 5: Commit**

```bash
git add docs/ACTIONS.md docs/API.md docs/ADVANCED_USAGE.md docs/TESTING.md README.md CHANGELOG.md CLAUDE.md lib/resteze/version.rb
git commit -m "Document the actions DSL and bump version to 0.5.0

Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>"
```
