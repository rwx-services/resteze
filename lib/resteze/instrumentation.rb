module Resteze
  module Instrumentation
    def execute_request(method, path, ...)
      payload = { method: method, path: path, api_module: api_module.name }

      ActiveSupport::Notifications.instrument("request.#{api_module::INSTRUMENTATION_KEY}", payload) do
        super.tap do |response|
          payload[:status]     = response.http_status
          payload[:request_id] = response.request_id
        end
      end
    end
  end
end
