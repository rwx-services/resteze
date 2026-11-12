# Dependencies
require "action_dispatch/http/mime_type"
require "active_support/all"
require "faraday"
require "hashie"
require "logger"

require_relative "resteze/version"

# API Concerns
require "resteze/api_module"
require "resteze/request"
require "resteze/actions/validation"
require "resteze/actions"
require "resteze/api_resource"
require "resteze/list"
require "resteze/save"

# API resource support classes
require "resteze/object"

# API Classes
require "resteze/instrumentation"
require "resteze/synchronized_state"
require "resteze/rate_limit"
require "resteze/rate_limiter"
require "resteze/rate_limiting"
require "resteze/authenticator"
require "resteze/authenticating"
require "resteze/client"
require "resteze/errors"
require "resteze/list_object"
require "resteze/response"
require "resteze/result"
require "resteze/util"
require "resteze/action"

# Middlewares
require "resteze/middleware/raise_error"

module Resteze
  extend ActiveSupport::Concern

  module ClassMethods
    def configure
      yield self
    end

    def default_service_path(_klass)
      "/"
    end

    def default_api_version(_klass)
      nil
    end

    def default_resource_slug(klass)
      klass.name.demodulize.underscore.pluralize
    end

    def default_object_key(_klass)
      nil
    end

    def default_list_key(_klass)
      :data
    end

    def default_api_key(attribute)
      attribute.to_s
    end

    def default_id_param(klass)
      :"#{klass.resource_slug.singularize}_id"
    end

    ACTION_DEFAULT_OPTIONS = %i[method id id_param].freeze

    # Declares API-wide defaults for one named action; resources merge these
    # beneath their own declarations.
    def action(name, **options)
      name = name.to_sym
      Resteze::Action.validate_options!(name, options)
      action_declarations[name] = options
      nil
    end

    def action_declarations
      @action_declarations ||= {}
    end

    # With options, merges them into the API-wide defaults applied to every
    # action; without options, returns those defaults.
    def action_defaults(**options)
      @action_defaults ||= {}
      return @action_defaults if options.empty?

      Resteze::Action.validate_options!(:defaults, options, allowed: ACTION_DEFAULT_OPTIONS)
      @action_defaults.merge!(options)
      nil
    end

    # Chooses how the API authenticates, without opening the module's
    # Authenticator: `authenticate_with :api_key, header: "X-Api-Key",
    # value: -> { MyApi.api_key }`. Call it once per scheme to combine
    # them. Reopen MyApi::Authenticator only to override its lifecycle.
    def authenticate_with(name, **)
      component_class(:Authenticator).strategy(name, **)
    end

    # Chooses how the client paces itself, without opening the module's
    # RateLimiter: `rate_limit_with :fixed_window, limit: 100, window: 60`.
    # Reopen MyApi::RateLimiter to override `retry?` and the rest.
    def rate_limit_with(name, **)
      component_class(:RateLimiter).strategy(name, **)
    end

    private

    def component_class(name)
      raise ArgumentError, "call this on a module that includes Resteze, after the include" unless include?(Resteze)

      const_get(name, false)
    end
  end

  extend ClassMethods

  included do
    class << self
      attr_accessor :api_base,
                    :open_timeout,
                    :read_timeout,
                    :logger,
                    :proxy

      # One RateLimiter per API module, shared by every thread. Defaults to
      # an instance of the module's own RateLimiter class; assign another to
      # replace it (nil restores the default). Whatever is assigned is told
      # which module it serves, so it raises this module's errors.
      def rate_limiter
        @rate_limiter || @component_mutex.synchronize { @rate_limiter ||= adopt(self::RateLimiter.new) }
      end

      def rate_limiter=(limiter)
        @rate_limiter = adopt(limiter)
      end

      # One Authenticator per API module, shared by every thread, with the
      # same defaults and replacement rules as rate_limiter.
      def authenticator
        @authenticator || @component_mutex.synchronize { @authenticator ||= adopt(self::Authenticator.new) }
      end

      def authenticator=(authenticator)
        @authenticator = adopt(authenticator)
      end

      # Tells a shared component which module it serves, so a replacement
      # of any class raises this module's errors.
      def adopt(component)
        component.api_module = self if component.respond_to?(:api_module=)
        component
      end
    end
    @component_mutex = Mutex.new

    configure do |config|
      config.api_base = "http://example.com/"
      config.open_timeout = 30
      config.read_timeout = 60
      config.logger = Logger.new($stdout)
    end

    # Setup magic constants
    const_set :INSTRUMENTATION_KEY, name.underscore.tr("/", "_") unless const_defined?("#{self}::INSTRUMENTATION_KEY")
    const_set :Object,      Class.new(Resteze::Object)
    const_set :Client,      Class.new(Resteze::Client)
    const_set :Response,    Class.new(Resteze::Response)
    const_set :Result,      Class.new(Resteze::Result)
    const_set :Error,       Class.new(Resteze::Error)
    const_set :RateLimiter,   Class.new(Resteze::RateLimiter)
    const_set :Authenticator, Class.new(Resteze::Authenticator)
    Resteze::Errors.define(self, self::Error)

    # Namespace other exceptions that we want to be able to catch and make sense of
    # without needing lower level implementation details
    const_set :NotImplementedError, Class.new(NotImplementedError)

    # Setup our Magic Constants
    const_set(:ListObject, Class.new(Hashie::Array)).class_eval do
      include ApiModule
      prepend Resteze::ListObject
    end

    const_set(:ApiResource, Class.new(self::Object)).class_eval do
      include Resteze::ApiResource
    end

    const_set(:Middleware, Module.new).module_eval do
      const_set :RaiseError, Class.new(Resteze::Middleware::RaiseError)
    end

    const_set(:List, Module.new).module_eval do
      extend ActiveSupport::Concern
      include Resteze::List
    end

    const_set(:Save, Module.new).module_eval do
      extend ActiveSupport::Concern
      include Resteze::Save
    end

    const_set(:Util, Module.new).module_eval do
      include Resteze::Util
    end
  end
end
