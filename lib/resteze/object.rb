module Resteze
  class Object < Hashie::Trash
    include Resteze::ApiModule
    include Hashie::Extensions::DeepMerge

    attr_reader :resteze_metadata, :property_bag

    def initialize(attributes = {}, &)
      @resteze_metadata = {}
      @property_bag = {}

      super
    end

    # This allows us to take advantage of the #property features of
    # the Hashie::Dash, but also to support unexpected hash values
    # and store them in the metadata property
    def []=(property, value)
      super
    rescue NoMethodError
      @property_bag = property_bag.merge({ property => value })
    end

    def self.class_name
      name.demodulize
    end

    def self.object_key
      api_module.default_object_key(self)
    end

    def self.construct_from(payload)
      new.initialize_from(payload)
    end

    # This is replaced with the idea of Hashie in Channel Advisor
    def initialize_from(values)
      values = values.deep_symbolize_keys
      if self.class.object_key
        update_attributes(values[self.class.object_key] || {})
      else
        update_attributes(values)
      end
      populate_metadata(values)
      self
    end

    def merge_from(values)
      values = values.deep_symbolize_keys
      if self.class.object_key
        data = values[self.class.object_key] || {}
        metadata = values.except(self.class.object_key) || {}
      else
        data = values
        metadata = {}
      end

      deep_merge!(data)
      @resteze_metadata.deep_merge!(metadata)
      self
    end

    def persisted?
      respond_to?(:id) && id.present?
    end

    private

    def populate_metadata(values)
      @resteze_metadata = values.except(self.class.object_key)
    end
  end
end
