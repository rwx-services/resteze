module Resteze
  # Opt-in mixin that adds #destroy and .destroy(id), routed through the
  # built-in :destroy action (DELETE /slug/:id unless re-routed).
  module Destroy
    extend ActiveSupport::Concern

    def destroy
      resp = request(
        destroy_method,
        destroy_resource_path,
        params: destroy_params,
        headers: destroy_headers
      )
      process_destroy_response(resp)
    end

    def destroy_method
      destroy_action.http_method
    end

    # While :destroy keeps its REST default, an instance-level resource_path
    # override is honored, as #refresh does for :retrieve.
    def destroy_resource_path
      return resource_path if destroy_action.rest_default?

      raise_invalid_destroy_id! if id.blank?
      destroy_action.path_for(id)
    end

    # The id param when the :destroy action carries the id as a param rather
    # than in the path; otherwise nothing.
    def destroy_params
      return {} unless destroy_action.id == :param

      { destroy_action.id_param => id }
    end

    def destroy_headers
      respond_to?(:retrieve_headers) ? retrieve_headers : {}
    end

    # Override to turn the response into something else. The default is a
    # Result, which is empty for a 204.
    def process_destroy_response(response)
      api_module::Result.from_response(response)
    end

    module ClassMethods
      def destroy(id)
        new(id).destroy
      end
    end

    private

    def destroy_action
      self.class.action_for(:destroy)
    end

    def raise_invalid_destroy_id!
      raise api_module::InvalidRequestError.new(
        "Could not determine which PATH to request: #{self.class} instance has invalid ID: #{id.inspect}", "id"
      )
    end
  end
end
