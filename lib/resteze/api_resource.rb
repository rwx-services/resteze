module Resteze
  module ApiResource
    extend ActiveSupport::Concern
    include Resteze::Request
    include Resteze::Actions
    include Resteze::PathTemplate

    # Keywords other than values: are path context, accepted only by a class
    # that declares a path_template: its tokens, and parent:.
    def initialize(id = nil, values: {}, **path_context)
      super(values)
      id, @retrieve_params = util.normalize_id(id)
      self.id = id if self.class.property?(:id)
      assign_path_context(*self.class.path_context!(path_context))
    end

    def resource_path
      unless id.present?
        raise api_module::InvalidRequestError.new("Could not determine which PATH to request: #{self.class} instance has " \
                                                  "invalid ID: #{id.inspect}", "id")
      end

      self.class.resource_path(id, **routing_path_params)
    end

    # The path #refresh requests: the routed :retrieve action. Unlike
    # #resource_path, this follows re-routing (e.g. /campaigns/details). While
    # :retrieve keeps its REST default, an instance-level resource_path
    # override is honored exactly as in 0.4.0.
    def retrieve_resource_path
      return resource_path if retrieve_action.rest_default?

      unless id.present?
        raise api_module::InvalidRequestError.new("Could not determine which PATH to request: #{self.class} instance has " \
                                                  "invalid ID: #{id.inspect}", "id")
      end

      retrieve_action.path_for(id, routing_path_params)
    end

    def retrieve_method
      retrieve_action.http_method
    end

    def retrieve_params
      params = @retrieve_params || {}
      return params unless retrieve_action.id == :param

      { retrieve_action.id_param => id }.merge(params)
    end

    def retrieve_headers
      {}
    end

    def refresh
      resp = request(
        retrieve_method,
        retrieve_resource_path,
        params: retrieve_params,
        headers: retrieve_headers
      )

      initialize_from(resp.data)
    end

    module ClassMethods
      def service_path
        api_module.default_service_path(self)
      end

      def api_version
        api_module.default_api_version(self)
      end

      def api_path(path)
        [service_path, api_version, path].join("/".freeze).squeeze("/".freeze)
      end

      def resource_slug
        api_module.default_resource_slug(self)
      end

      # The slug, or the filled path_template, followed by the id. Path
      # values are only accepted by a class that declares a path_template.
      # An id that is blank, "." or ".." raises InvalidRequestError; pass no
      # id for the collection path.
      def resource_path(id = nil, **path_params)
        encoded_id = Resteze::Util.encode_path_segment(path_value!(:id, id)) unless id.nil?
        api_path([*resource_segments(path_params), encoded_id].compact.join("/".freeze))
      end

      # The id is positional, or the keywords themselves in the hash form
      # (`retrieve(id: "abc", expand: true)`). A templated class takes its
      # path values and parent: out of the keywords first.
      def retrieve(id = nil, **keywords)
        path_params, parent, rest = partition_path_keywords(keywords)
        if id.nil?
          id = rest
        else
          reject_unknown_keywords!(rest)
        end

        new(id).assign_path_context(path_params, parent).refresh
      end
    end

    private

    def retrieve_action
      self.class.action_for(:retrieve)
    end
  end
end
