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

  class TrackResult < Object
    property :message
    property :events_processed
  end

  class Campaign < ApiResource
    include List

    property :id
    property :name

    action :data_series, method: :get
    action :duplicate,   method: :post, on: :member, returns: :self
    action :featured,    method: :get, returns: :self
    action :search,      method: :get, returns: :list
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
    action :track_typed, method: :post, path: "track", returns: TrackResult
  end
end

VerbApi.configure do |config|
  config.api_base = "http://verb.example.com/"
  config.logger = Logger.new(nil)
end

module WrapApi
  include Resteze

  def self.default_object_key(_klass)
    :item
  end

  class Thing < ApiResource
    property :id

    action :featured, method: :get, returns: :self
  end
end

WrapApi.configure do |config|
  config.api_base = "http://wrap.example.com/"
  config.logger = Logger.new(nil)
end

# An API that reports failures inside a 2xx body, Braze-style:
# { "message": "success" } or { "message": "...", "errors": [...] }.
module BodyApi
  include Resteze

  class Response
    SUCCESS = %w[success queued].freeze

    def self.body_error(response)
      data = response.data
      return unless data.is_a?(Hash)
      return if SUCCESS.include?(data[:message]) && data[:errors].blank?

      ApiError.from_response(response, data[:message] || "errors in response body")
    end
  end

  # Braze-style: quota in X-RateLimit-* headers, retry a 429 twice.
  class RateLimiter
    def before_request(*, **)
      synchronize { |state| state[:requests] = state.fetch(:requests, 0) + 1 }
      super
    end

    def track(response)
      limit = rate_limit(response)
      update_state(remaining: limit.remaining, reset: limit.reset) if limit
    end

    def rate_limit(response)
      Resteze::RateLimit.from_headers(response.http_headers)
    end

    def retry?(_error, attempt)
      attempt <= 2
    end

    def retry_after(error)
      error.retry_after || 0
    end
  end

  class User < ApiResource
    action :track, method: :post
  end
end

BodyApi.configure do |config|
  config.api_base = "http://body.example.com/"
  config.logger = Logger.new(nil)
end

# A scheme defined the way a built-in is: a Strategy subclass whose
# DEFAULTS name the module setting it expects.
class HeaderKey < Resteze::Authenticator::Strategy
  DEFAULTS = { value: :api_key }.freeze

  attr_reader :header

  def initialize(value: :api_key, header: "X-Api-Key")
    super()
    @value  = value
    @header = header
  end

  def apply(request, _state)
    request.headers[header] = resolve!(:value, @value).to_s
  end
end

# An API authenticated with a header key read from AuthApi.api_key.
module AuthApi
  include Resteze

  authenticate_with HeaderKey # expects AuthApi.api_key

  class Widget < ApiResource
    include Save

    property :id
    property :name
  end
end

AuthApi.configure do |config|
  config.api_base = "http://auth.example.com/"
  config.api_key  = "secret-key"
  config.logger   = Logger.new(nil)
end

# Configured entirely through the module-level macros.
module MacroApi
  include Resteze

  authenticate_with HeaderKey, value: "k"
  authenticate_with HeaderKey, header: "X-Second", value: :second_key
  rate_limit_with :token_bucket, capacity: 5, refill_rate: 1
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
