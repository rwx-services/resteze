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
require "resteze/api_resource"
require "resteze/list"
require "resteze/save"

# API resource support classes
require "resteze/object"

# API Classes
require "resteze/client"
require "resteze/errors"
require "resteze/list_object"
require "resteze/response"
require "resteze/util"

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
  end

  extend ClassMethods

  included do
    class << self
      attr_accessor :api_base,
                    :open_timeout,
                    :read_timeout,
                    :logger,
                    :proxy
    end

    configure do |config|
      config.api_base = "http://example.com/"
      config.open_timeout = 30
      config.read_timeout = 60
      config.logger = Logger.new($stdout)
    end

    # Setup magic constants
    const_set :Object,      Class.new(Resteze::Object)
    const_set :Client,      Class.new(Resteze::Client)
    const_set :Response,    Class.new(Resteze::Response)
    const_set :Error,       Class.new(Resteze::Error)

    Resteze::Error.subclasses.select { |klass| klass.name.start_with?("Resteze::") }.each do |error_class|
      error_type = error_class.to_s.demodulize
      const_set error_type, Class.new(error_class) unless const_defined?("#{self}::#{error_type}")
    end

    # Namespace other exceptions that we want to be able to catch and make sense of
    # without needing lower level implementation details
    const_set :NotImplementedError, Class.new(NotImplementedError)
    const_set :ResourceNotFound, Class.new(Faraday::ResourceNotFound)
    const_set :UnprocessableEntityError, Class.new(Faraday::UnprocessableEntityError)
    const_set :ConflictError, Class.new(Faraday::ConflictError)

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
