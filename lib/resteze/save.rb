module Resteze
  module Save
    extend ActiveSupport::Concern

    def save
      resp = request(
        save_method,
        save_resource_path,
        params: as_save_json,
        headers: save_headers
      )
      process_save_response(resp)
    end

    def save_method
      persisted? ? :put : :post
    end

    def save_resource_path
      persisted? ? resource_path : self.class.resource_path
    end

    def as_save_json
      as_json
    end

    def save_headers
      respond_to?(:retrieve_headers) ? retrieve_headers : {}
    end

    def process_save_response(response)
      merge_from(response.data)
    end
  end
end
