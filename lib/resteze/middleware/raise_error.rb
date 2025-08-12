module Resteze
  module Middleware
    class RaiseError < Faraday::Response::RaiseError
      include Resteze::ApiModule

      def on_complete(env)
        super
      rescue Faraday::ConflictError => e
        raise api_module::ConflictError, e
      rescue Faraday::UnprocessableEntityError => e
        raise api_module::UnprocessableEntityError, e
      rescue Faraday::ResourceNotFound => e
        raise api_module::ResourceNotFound, e
      end
    end
  end
end
