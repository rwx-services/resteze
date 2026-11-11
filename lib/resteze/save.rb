module Resteze
  module Save
    extend ActiveSupport::Concern

    def save
      resp = request(
        save_method,
        save_resource_path,
        params: save_params,
        headers: save_headers
      )
      process_save_response(resp)
    end

    def save_method
      save_action.http_method
    end

    # While :create / :update keep their REST defaults, an instance-level
    # resource_path override is honored exactly as in 0.4.0.
    def save_resource_path
      action = save_action
      if action.rest_default?
        persisted? ? resource_path : self.class.resource_path
      else
        persisted? ? action.path_for(id) : action.path_for
      end
    end

    def as_save_json
      as_json
    end

    # The body sent by #save: as_save_json, plus the id param when the
    # :update action carries the id as a param rather than in the path.
    def save_params
      params = as_save_json
      return params unless persisted? && save_action.id == :param

      { save_action.id_param.to_s => id }.merge(params)
    end

    def save_headers
      respond_to?(:retrieve_headers) ? retrieve_headers : {}
    end

    def process_save_response(response)
      merge_from(response.data)
    end

    private

    def save_action
      self.class.actions.fetch(persisted? ? :update : :create)
    end
  end
end
