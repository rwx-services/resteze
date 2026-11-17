module Resteze
  module Util
    extend ActiveSupport::Concern

    DOT_SEGMENTS = %w[. ..].freeze

    module ClassMethods
      def convert_to_object(data, object_class)
        case data
        when Array
          data.map { |i| convert_to_object(i, object_class) }
        when Hash
          object_class.construct_from(object_class.object_key.present? ? { object_class.object_key => data } : data)
        else
          data
        end
      end

      # Encodes a value for use as one segment of a URL path. This is
      # percent-encoding, not form encoding: a space becomes %20, where
      # CGI.escape would write a "+" that a server reads literally in a path.
      def encode_path_segment(value)
        ERB::Util.url_encode(value.to_s)
      end

      # True for "." and "..", which a URL resolves as "this directory" and
      # "up one": as a path segment either would leave the intended path.
      def dot_segment?(value)
        DOT_SEGMENTS.include?(value.to_s)
      end

      def normalize_headers(headers)
        headers.transform_keys { |key| capitalize_parts(key) }
      end

      def normalize_id(id)
        if id.is_a?(Hash)
          params_hash = id.dup
          id = params_hash.delete(:id)
        else
          params_hash = {}
        end

        [id.to_s.presence, params_hash]
      end

      def objects_to_ids(obj)
        case obj
        when ApiResource
          obj.id
        when Hash
          res = {}
          obj.each { |k, v| res[k] = objects_to_ids(v) unless v.nil? }
          res
        when Array
          obj.map { |v| objects_to_ids(v) }
        else
          obj
        end
      end

      def capitalize_parts(str)
        str.to_s.dasherize.split("-").reject(&:blank?).map(&:capitalize).join("-")
      end
    end

    extend ClassMethods
  end
end
