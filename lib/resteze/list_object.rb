module Resteze
  module ListObject
    extend ActiveSupport::Concern

    def metadata
      @metadata ||= {}
    end

    def initialize_from(values, metadata: {})
      @metadata = metadata
      values.each { |v| self << v }
      self
    end

    def as_list_json(list_key)
      metadata.as_json.merge({ list_key => as_json })
    end

    module ClassMethods
      def object_key
        :_list
      end

      def construct_from(payload, klass)
        list_key = klass.list_key
        payload = payload.deep_symbolize_keys
        values = util.convert_to_object(payload[list_key], klass)
        metadata = payload.except(list_key)

        new.initialize_from(values, metadata:)
      end
    end

    private

    def populate_metadata(values)
      @metadata = metadata.merge(values.except(self.class.object_key) || {})
    end
  end
end
