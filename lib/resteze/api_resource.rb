module Resteze
  module ApiResource
    extend ActiveSupport::Concern
    include Resteze::Request

    def initialize(id = nil, values: {})
      super(values)
      id, @retrieve_params = util.normalize_id(id)
      self.id = id if self.class.property?(:id)
    end

    def resource_path
      unless id.present?
        raise api_module::InvalidRequestError.new("Could not determine which PATH to request: #{self.class} instance has " \
                                                  "invalid ID: #{id.inspect}", "id")
      end

      self.class.resource_path(id)
    end

    def retrieve_method
      :get
    end

    def retrieve_params
      @retrieve_params || {}
    end

    def retrieve_headers
      {}
    end

    def refresh
      resp = request(
        retrieve_method,
        resource_path,
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

      def resource_path(id = nil)
        api_path([resource_slug, id].compact.map { |part| CGI.escape(part.to_s) }.join("/".freeze))
      end

      def retrieve(id)
        new(id).refresh
      end
    end
  end
end
