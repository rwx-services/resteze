if ENV["COVERAGE"]
  require "simplecov"
  SimpleCov.start
end
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "webmock/minitest"
require "resty"
require "debug"

require "minitest/reporters"
Minitest::Reporters.use!

WebMock.disable_net_connect!

module AcmeApi
  include Resty

  class << self
    attr_accessor :api_key
  end

  class Widget < ApiResource
    include Resty::List

    property :id
    property :foo
  end

  class Gadget < Widget; end

  class GizmoDevice < Widget
    def self.resource_path
      api_path("gizmos")
    end
  end
end

def configure_gem!
  AcmeApi.configure do |config|
    config.api_base = "http://acme.example.com/"
    config.open_timeout = 30
    config.read_timeout = 60
    config.logger = Logger.new($stdout)
  end
end

def reset_gem!
  configure_gem!
end

configure_gem!

module Minitest
  class Spec
    make_my_diffs_pretty!

    def api_url(path)
      AcmeApi::Client.api_url(AcmeApi::ApiResource.api_path(path))
    end
  end
end
