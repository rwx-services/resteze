module Resteze
  module List
    extend ActiveSupport::Concern
    include ApiModule

    module ClassMethods
      # Keywords other than params: are path context, accepted only by a
      # class that declares a path_template.
      def list(params: {}, **path_context)
        path_params, parent = path_context!(path_context)
        resp = request(list_method, list_resource_path(params, **path_params), params: list_params(params))
        apply_path_context(construct_list_from(resp.data), path_params, parent)
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

      def list_resource_path(_params = {}, **path_params)
        action_for(:list).path_for(nil, path_params)
      end

      def list_key
        api_module.default_list_key(self)
      end

      def list_method
        action_for(:list).http_method
      end
    end
  end
end
