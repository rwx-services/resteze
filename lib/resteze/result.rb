module Resteze
  # The default return value of a custom action: a loose, dot-accessible view
  # of the parsed response body, with the Response it came from attached.
  class Result < Hashie::Mash
    include Resteze::ApiModule

    disable_warnings

    attr_reader :http_response

    def self.from_response(response)
      data = response.data
      new(data.is_a?(Hash) ? data : {}).tap do |result|
        result.instance_variable_set(:@http_response, response)
      end
    end
  end
end
