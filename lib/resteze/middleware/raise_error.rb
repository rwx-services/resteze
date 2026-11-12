module Resteze
  module Middleware
    class RaiseError < Faraday::Response::RaiseError
      include Resteze::ApiModule

      def on_complete(env)
        super
      rescue Faraday::ConflictError => e
        raise api_module::ConflictError.new(e, e.response)
      rescue Faraday::UnprocessableEntityError => e
        raise api_module::UnprocessableEntityError.new(e, e.response)
      rescue Faraday::ResourceNotFound => e
        raise api_module::ResourceNotFound.new(e, e.response)
      end
    end
  end
end
