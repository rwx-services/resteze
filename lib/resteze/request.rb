module Resteze
  module Request
    extend ActiveSupport::Concern
    include Resteze::ApiModule

    delegate :request, to: :class

    module ClassMethods
      def request(method, url, params: {}, headers: {})
        api_module::Client.active_client.execute_request(method, url, params:, headers:)
      end
    end
  end
end
