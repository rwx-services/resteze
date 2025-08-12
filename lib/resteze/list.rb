module Resteze
  module List
    extend ActiveSupport::Concern
    include ApiModule

    module ClassMethods
      def list(params: {})
        resp = request(list_method, list_resource_path(params), params: list_params(params))
        construct_list_from(resp.data)
      end

      def construct_list_from(payload)
        values = payload.deep_symbolize_keys
        api_module::ListObject.construct_from(values, self)
      end

      def construct_empty_list
        payload = { list_key => [] }
        construct_list_from(payload)
      end

      def list_params(params = {})
        params
      end

      def list_headers(_params = {})
        {}
      end

      def list_resource_path(_params = {})
        resource_path
      end

      def list_key
        api_module.default_list_key(self)
      end

      def list_method
        :get
      end
    end
  end
end
