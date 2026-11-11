module Resteze
  # A resolved action on a resource class: the HTTP method, route and return
  # type for one named operation such as :retrieve or :track.
  class Action
    OPTIONS  = %i[method on path id id_param returns as].freeze
    RESERVED = %i[retrieve list create update].freeze
    BUILT_IN = {
      retrieve: { method: :get, on: :member, path: nil, id: :path },
      list: { method: :get, on: :collection, path: nil },
      create: { method: :post, on: :collection, path: nil },
      update: { method: :put, on: :member, path: nil, id: :path }
    }.freeze

    attr_reader :name, :owner, :on, :path, :id, :returns, :as

    def initialize(name, owner, options = {})
      @name    = name.to_sym
      @owner   = owner
      @options = options.slice(*OPTIONS)
      @on      = @options[:on] || BUILT_IN.dig(@name, :on) || :collection
      @options = @options.except(:id, :id_param) if collection?
      @path    = @options.fetch(:path) { reserved? ? nil : @name.to_s }
      @id      = member? ? @options.fetch(:id, :path) : nil
      @returns = @options[:returns]
      @as      = @options[:as]
    end

    def reserved?
      RESERVED.include?(name)
    end

    def member?
      on == :member
    end

    def collection?
      !member?
    end

    def generated_name
      (as || name).to_sym
    end

    def http_method
      @options[:method] or raise ArgumentError,
                                 "Action :#{name} on #{owner} has no HTTP method; " \
                                 "declare it with method: on the resource or at module level"
    end

    def id_param
      @options[:id_param] ||
        (owner.id_param if owner.respond_to?(:id_param)) ||
        owner.api_module.default_id_param(owner)
    end

    def path_segments
      path.to_s.split("/").reject(&:blank?).map { |part| CGI.escape(part) }
    end

    def path_for(id = nil)
      base = member? && self.id == :path ? owner.resource_path(id) : owner.resource_path
      [base, *path_segments].join("/").squeeze("/")
    end

    def to_h
      {
        name:, method: @options[:method], on:, path:, id:,
        id_param: (id_param if member?), returns:, as: generated_name
      }
    end
  end
end
