if ENV["COVERAGE"]
  require "simplecov"

  SimpleCov.start
end
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)

require "minitest/autorun"
require "webmock/minitest"
require "resteze"
require "debug"

require "minitest/reporters"
Minitest::Reporters.use!

WebMock.disable_net_connect!

module AcmeApi
  include Resteze

  class << self
    attr_accessor :api_key
  end

  class Widget < ApiResource
    include Resteze::List

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

module VerbApi
  include Resteze

  action_defaults id: :param

  action :retrieve, path: "details"
  action :list,     path: "list"
  action :create,   path: "create"
  action :update,   path: "update", method: :post
  action :export,   method: :post

  def self.default_list_key(klass)
    klass.resource_slug.to_sym
  end

  class Campaign < ApiResource
    include List

    property :id
    property :name

    action :data_series, method: :get
    action :duplicate,   method: :post, on: :member
  end

  class SpecialCampaign < Campaign
    action :duplicate, path: "clone"
  end

  class ContentBlock < ApiResource
    include List
    include Save

    property :id
    property :content

    action :retrieve, path: "info"
  end

  class User < ApiResource
    property :external_id

    action :track, method: :post
    action :export
    action :export_ids, method: :post, path: "export/ids"
  end
end

VerbApi.configure do |config|
  config.api_base = "http://verb.example.com/"
  config.logger = Logger.new(nil)
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

    def verb_url(path)
      VerbApi::Client.api_url(VerbApi::ApiResource.api_path(path))
    end
  end
end
