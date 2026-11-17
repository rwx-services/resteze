require "test_helper"

module Resteze
  class PathTemplateTest < Minitest::Spec
    # rubocop:disable Style/ClassAndModuleChildren
    # A 1.0.0 consumer overriding invoke_action with its original signature.
    class VerbApi::Probe < VerbApi::ApiResource
      property :id

      action :ping, method: :post, on: :member, id: :path
      action :sweep, method: :post

      def self.invoke_action(name, params = {}, id: nil) = super(name, params.merge(audit: true), id:)
    end

    # A 1.0.0 consumer whose resource has a property named path_params.
    class AcmeApi::Route < AcmeApi::ApiResource
      property :id
      property :path_params
    end
    # rubocop:enable Style/ClassAndModuleChildren

    Item    = NestApi::Item
    Catalog = NestApi::Catalog

    def nest_url(path)
      "http://nest.example.com#{path}"
    end

    def json(body)
      { body: body.to_json, headers: { "Content-Type" => "application/json" } }
    end

    def declare(template)
      Class.new(NestApi::ApiResource) do
        def self.name = "NestApi::Scratch"
        property :id
        path_template template
      end
    end

    describe ".path_template" do
      it "exposes the template and its tokens" do
        assert_equal "catalogs/:catalog_name/items", Item.path_template
        assert_equal [:catalog_name], Item.path_tokens
        assert_equal %i[catalog_name item_id], NestApi::Variant.path_tokens
        assert_predicate Item, :nested?
        assert_predicate NestApi::SaleItem, :nested?
        assert_predicate Item.new("sku1"), :nested?
      end

      it "is absent on a plain resource" do
        assert_nil Catalog.path_template
        assert_empty Catalog.path_tokens
        refute_predicate Catalog, :nested?
        refute_predicate Catalog.new, :nested?
      end

      it "is inherited and can be redeclared" do
        assert_equal [:catalog_name], NestApi::SaleItem.path_tokens

        subclass = Class.new(Item) { path_template "shops/:shop_id/items" }

        assert_equal [:shop_id], subclass.path_tokens
        assert_equal [:catalog_name], Item.path_tokens
      end

      it "leaves resource_slug alone" do
        assert_equal "items", Item.resource_slug
      end

      it "rejects a template with no tokens" do
        error = assert_raises(ArgumentError) { declare("catalogs/items") }

        assert_match(/no :tokens/, error.message)
      end

      it "rejects a duplicate token" do
        assert_raises(ArgumentError) { declare("a/:x/b/:x") }
      end

      it "rejects reserved token names" do
        %w[id params values parent].each do |name|
          error = assert_raises(ArgumentError) { declare("things/:#{name}/parts") }

          assert_match(/reserved/, error.message)
        end
      end

      it "rejects a token that is only part of a segment" do
        assert_raises(ArgumentError) { declare("catalogs/v:version/items") }
        assert_raises(ArgumentError) { declare("catalogs/:Bad-Name/items") }
      end

      it "rejects a token whose reader would shadow an existing method" do
        error = assert_raises(ArgumentError) { declare("stores/:key/items") }

        assert_match(/key/, error.message)
      end
    end

    describe ".resource_path" do
      it "fills the template" do
        assert_equal "/catalogs/shoes/items", Item.resource_path(catalog_name: "shoes")
        assert_equal "/catalogs/shoes/items/sku1", Item.resource_path("sku1", catalog_name: "shoes")
      end

      it "fills several tokens" do
        assert_equal "/catalogs/shoes/items/sku1/variants/v2",
                     NestApi::Variant.resource_path("v2", catalog_name: "shoes", item_id: "sku1")
      end

      it "escapes path values as it escapes the id" do
        assert_equal "/catalogs/a%2Fb/items/sku%201", Item.resource_path("sku 1", catalog_name: "a/b")
        assert_equal "/catalogs/red%20shoes/items", Item.resource_path(catalog_name: "red shoes")
      end

      it "raises InvalidRequestError naming a missing or blank value" do
        [{}, { catalog_name: "" }, { catalog_name: nil }].each do |values|
          error = assert_raises(NestApi::InvalidRequestError) { Item.resource_path("sku1", **values) }

          assert_equal "catalog_name", error.param
          assert_match(/catalog_name/, error.message)
        end
      end

      it "refuses a dot segment, which would climb out of the template" do
        %w[. ..].each do |value|
          error = assert_raises(NestApi::InvalidRequestError) { Item.resource_path("sku1", catalog_name: value) }

          assert_equal "catalog_name", error.param
        end
        assert_equal "/catalogs/..a/items", Item.resource_path(catalog_name: "..a")
      end

      it "rejects an unknown keyword" do
        assert_raises(ArgumentError) { Item.resource_path("sku1", catalog_name: "shoes", colour: "red") }
      end

      it "rejects keywords on a plain resource" do
        assert_raises(ArgumentError) { Catalog.resource_path("shoes", catalog_name: "shoes") }
      end
    end

    describe "Action#path_for" do
      it "nests member, collection and id-as-param actions" do
        values = { catalog_name: "shoes" }

        assert_equal "/catalogs/shoes/items/sku1/archive", Item.action_for(:archive).path_for("sku1", values)
        assert_equal "/catalogs/shoes/items/bulk_update", Item.action_for(:bulk_update).path_for(nil, values)
        assert_equal "/catalogs/shoes/items/lookup", Item.action_for(:lookup).path_for("sku1", values)
        assert_equal "/catalogs/shoes/items/sku1", Item.action_for(:retrieve).path_for("sku1", values)
      end
    end

    describe ".new" do
      it "remembers path values and the parent" do
        catalog = Catalog.new(values: { name: "shoes" })
        item = Item.new("sku1", catalog_name: "shoes", parent: catalog, values: { price: 10 })

        assert_equal({ catalog_name: "shoes" }, item.path_params)
        assert_predicate item.path_params, :frozen?
        assert_equal "shoes", item.catalog_name
        assert_same catalog, item.parent
        assert_same catalog, item.path_parent
        assert_equal "/catalogs/shoes/items/sku1", item.resource_path
      end

      it "allows values to be missing until a path is needed" do
        item = Item.new("sku1")

        assert_empty item.path_params
        assert_nil item.catalog_name
        assert_nil item.parent
        error = assert_raises(NestApi::InvalidRequestError) { item.resource_path }

        assert_equal "catalog_name", error.param
      end

      it "rejects an unknown keyword" do
        assert_raises(ArgumentError) { Item.new("sku1", colour: "red") }
        assert_raises(ArgumentError) { Catalog.new("shoes", catalog_name: "shoes") }
        assert_raises(ArgumentError) { Catalog.new("shoes", parent: Object.new) }
      end

      it "keeps path values and the parent out of the serialized object" do
        item = Item.new("sku1", catalog_name: "shoes", parent: Catalog.new, values: { price: 10 })

        assert_equal({ "id" => "sku1", "price" => 10 }, item.as_json)
      end

      it "prefers an explicit value and falls back to a property of the same name" do
        echoed = NestApi::Field.new("f1", values: { catalog_name: "from-body" })

        assert_equal({ catalog_name: "from-body" }, echoed.path_params)
        assert_equal "/catalogs/from-body/fields/f1", echoed.resource_path

        explicit = NestApi::Field.new("f1", catalog_name: "explicit", values: { catalog_name: "from-body" })

        assert_equal "/catalogs/explicit/fields/f1", explicit.resource_path
        assert_equal "from-body", explicit.catalog_name
      end
    end

    describe "name collisions" do
      it "keeps the reader of a property inherited from a superclass" do
        child = Class.new(NestApi::Field) { path_template "shops/:catalog_name/fields" }
        field = child.new("f1", catalog_name: "explicit", values: { catalog_name: "from-body" })

        assert_equal "from-body", field.catalog_name
        assert_equal "/shops/explicit/fields/f1", field.resource_path
      end

      it "leaves a plain resource with a path_params property working" do
        klass = AcmeApi::Route

        assert_equal "/routes/r1", klass.new("r1", values: { path_params: { a: 1 } }).resource_path
      end
    end

    describe ".retrieve" do
      it "requests the nested path and keeps the context" do
        stub = stub_request(:get, nest_url("/catalogs/shoes/items/sku1")).to_return(json(id: "sku1", price: 10))
        catalog = Catalog.new
        item = Item.retrieve("sku1", catalog_name: "shoes", parent: catalog)

        assert_requested stub
        assert_equal 10, item.price
        assert_equal "shoes", item.catalog_name
        assert_same catalog, item.parent
      end

      it "accepts the braceless hash id alongside path values" do
        stub = stub_request(:get, nest_url("/catalogs/shoes/items/sku1"))
               .with(query: { expand: "true" }).to_return(json(id: "sku1"))

        Item.retrieve(id: "sku1", catalog_name: "shoes", expand: true)

        assert_requested stub
      end

      it "rejects a stray keyword next to a positional id" do
        assert_raises(ArgumentError) { Item.retrieve("sku1", catalog_name: "shoes", expand: true) }
      end

      it "still accepts the braceless hash id on a plain resource" do
        stub = stub_request(:get, api_url("/widgets/abc")).with(query: { expand: "true" }).to_return(json(id: "abc"))

        widget = AcmeApi::Widget.retrieve(id: "abc", expand: true)

        assert_requested stub
        assert_equal "abc", widget.id
      end

      it "rejects a keyword next to a positional id on a plain resource" do
        assert_raises(ArgumentError) { AcmeApi::Widget.retrieve("abc", expand: true) }
      end
    end

    describe "#refresh" do
      it "keeps the context" do
        stub_request(:get, nest_url("/catalogs/shoes/items/sku1")).to_return(json(id: "sku1", price: 12))
        catalog = Catalog.new
        item = Item.new("sku1", catalog_name: "shoes", parent: catalog).refresh

        assert_equal 12, item.price
        assert_equal({ catalog_name: "shoes" }, item.path_params)
        assert_same catalog, item.parent
      end
    end

    describe ".list" do
      it "requests the nested path and sends only params in the query" do
        stub = stub_request(:get, nest_url("/catalogs/shoes/items"))
               .with(query: { cursor: "abc" }).to_return(json(data: [{ id: "sku1" }, { id: "sku2" }]))

        items = Item.list(catalog_name: "shoes", params: { cursor: "abc" })

        assert_requested stub
        assert_equal %w[sku1 sku2], items.map(&:id)
        assert(items.all? { |item| item.path_params == { catalog_name: "shoes" } })
        assert_equal "/catalogs/shoes/items/sku2", items.last.resource_path
      end

      it "hands the parent to every item" do
        stub_request(:get, nest_url("/catalogs/shoes/items")).to_return(json(data: [{ id: "sku1" }]))
        catalog = Catalog.new(values: { name: "shoes" })

        assert_same catalog, catalog.items.first.parent
      end

      it "raises before any request when a value is missing" do
        error = assert_raises(NestApi::InvalidRequestError) { Item.list }

        assert_equal "catalog_name", error.param
      end

      it "rejects an unknown keyword" do
        assert_raises(ArgumentError) { Item.list(catalog_name: "shoes", colour: "red") }
        assert_raises(ArgumentError) { AcmeApi::Widget.list(parent: Object.new) }
      end
    end

    describe "#save" do
      it "creates under the nested collection without the path value in the body" do
        stub = stub_request(:post, nest_url("/catalogs/shoes/items"))
               .with(body: { price: 10 }.to_json).to_return(json(id: "sku9", price: 10))

        item = Item.new(catalog_name: "shoes", values: { price: 10 })
        item.save

        assert_requested stub
        assert_equal "sku9", item.id
        assert_equal "shoes", item.catalog_name
      end

      it "updates the nested member" do
        stub = stub_request(:put, nest_url("/catalogs/shoes/items/sku1"))
               .with(body: { id: "sku1", price: 11 }).to_return(json(id: "sku1", price: 11))

        Item.new("sku1", catalog_name: "shoes", values: { price: 11 }).save

        assert_requested stub
      end

      it "saves an item that came from a list" do
        stub_request(:get, nest_url("/catalogs/shoes/items")).to_return(json(data: [{ id: "sku1", price: 1 }]))
        stub = stub_request(:put, nest_url("/catalogs/shoes/items/sku1")).to_return(json(id: "sku1"))

        Item.list(catalog_name: "shoes").first.save

        assert_requested stub
      end
    end

    describe "actions" do
      it "routes a collection action and keeps path values out of the body" do
        stub = stub_request(:post, nest_url("/catalogs/shoes/items/bulk_update"))
               .with(body: { items: [1] }.to_json).to_return(json(message: "ok"))

        result = Item.bulk_update(catalog_name: "shoes", parent: Catalog.new, items: [1])

        assert_requested stub
        assert_equal "ok", result.message
      end

      it "routes the class form of a member action" do
        stub = stub_request(:post, nest_url("/catalogs/shoes/items/sku1/archive"))
               .with(body: { reason: "old" }.to_json).to_return(json(message: "ok"))

        Item.archive("sku1", catalog_name: "shoes", reason: "old")

        assert_requested stub
      end

      it "routes the instance form with the remembered values" do
        stub = stub_request(:post, nest_url("/catalogs/shoes/items/sku1/archive")).to_return(json(message: "ok"))

        Item.new("sku1", catalog_name: "shoes").archive

        assert_requested stub
      end

      it "treats every keyword of the instance form as a request param" do
        stub = stub_request(:post, nest_url("/catalogs/shoes/items/sku1/move"))
               .with(body: { catalog_name: "boots" }.to_json).to_return(json(message: "ok"))

        Item.new("sku1", catalog_name: "shoes").move(catalog_name: "boots")

        assert_requested stub
      end

      it "nests an action that carries the id as a param" do
        stub = stub_request(:get, nest_url("/catalogs/shoes/items/lookup"))
               .with(query: { item_id: "sku1" }).to_return(json(message: "ok"))

        Item.lookup("sku1", catalog_name: "shoes")

        assert_requested stub
      end

      it "gives the context to returns: :list results" do
        stub_request(:get, nest_url("/catalogs/shoes/items/search"))
          .with(query: { q: "red" }).to_return(json(data: [{ id: "sku1" }]))
        catalog = Catalog.new

        found = Item.search(catalog_name: "shoes", parent: catalog, q: "red")

        assert_equal "shoes", found.first.catalog_name
        assert_same catalog, found.first.parent
      end

      it "gives the context to returns: :self results" do
        stub_request(:post, nest_url("/catalogs/shoes/items/sku1/duplicate")).to_return(json(id: "sku2"))
        catalog = Catalog.new

        copy = Item.new("sku1", catalog_name: "shoes", parent: catalog).duplicate

        assert_equal "sku2", copy.id
        assert_equal "/catalogs/shoes/items/sku2", copy.resource_path
        assert_same catalog, copy.parent
      end

      it "raises before any request when a value is missing" do
        assert_raises(NestApi::InvalidRequestError) { Item.bulk_update(items: [1]) }
        assert_raises(NestApi::InvalidRequestError) { Item.archive("sku1") }
      end

      it "gives the context to results of returns: naming the class itself" do
        klass = Class.new(Item) { def self.name = "NestApi::Item" }
        klass.action :twin, method: :get, on: :member, returns: klass
        stub_request(:get, nest_url("/catalogs/shoes/items/sku1/twin")).to_return(json(id: "sku2"))

        assert_equal "shoes", klass.twin("sku1", catalog_name: "shoes").catalog_name
      end

      it "calls a 1.0.0-style invoke_action override on a plain resource" do
        klass = VerbApi::Probe
        ping  = stub_request(:post, verb_url("/probes/a/ping")).with(body: { audit: true }).to_return(json(ok: 1))
        sweep = stub_request(:post, verb_url("/probes/sweep")).with(body: { audit: true }).to_return(json(ok: 1))

        klass.ping("a")
        klass.sweep

        assert_requested ping
        assert_requested sweep
      end

      it "leaves parent as an ordinary param on a plain resource" do
        stub = stub_request(:post, verb_url("/users/track")).with(body: { parent: "p1" }.to_json)
                                                            .to_return(json(message: "ok"))

        VerbApi::User.track(parent: "p1")

        assert_requested stub
      end
    end
  end
end
