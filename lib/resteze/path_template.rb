module Resteze
  # Nested resources. `path_template "catalogs/:catalog_name/items"` on a
  # resource replaces its slug with a path whose :tokens are filled per call:
  # class methods take them as keywords (`Item.list(catalog_name: "shoes")`)
  # and instances remember them, so every action routes under the parent.
  # A `parent:` keyword rides along as a plain reference (`item.parent`).
  module PathTemplate
    extend ActiveSupport::Concern

    RESERVED = %i[id params values parent].freeze
    TOKEN    = /\A:([a-z_][a-z0-9_]*)\z/
    DOT_SEGMENTS = %w[. ..].freeze

    # Holds the generated readers. They sit behind the class's own methods,
    # so a property of the same name keeps its reader whichever is declared
    # first.
    class Readers < Module; end

    # The values that fill this instance's path: those it was given, falling
    # back to a property of the same name (for an API that echoes the
    # parent's id in the body).
    def path_params
      routing_path_params
    end

    def nested?
      self.class.nested?
    end

    # The object handed over as `parent:`, if any. Never fetched or
    # serialized. Also readable as #parent unless a property takes that name.
    def path_parent
      @path_parent
    end

    def assign_path_context(path_params, parent = nil)
      @path_params = (path_params || {}).slice(*self.class.path_params)
      @path_parent = parent
      self
    end

    private

    # What #path_params returns. Resteze routes with this, so a resource
    # that names a property `path_params` still routes correctly.
    def routing_path_params
      given = @path_params || {}
      self.class.path_params.to_h { |token| [token, given[token].presence || path_property(token)] }.compact.freeze
    end

    # The keywords that carry this instance's path context to invoke_action:
    # none for a class with no template, so a 1.0.0 override still fits.
    def action_path_context
      self.class.action_path_context(routing_path_params, path_parent)
    end

    def path_property(token)
      self[token].presence if self.class.property?(token)
    end

    module ClassMethods
      # With a template, declares it; without, returns the one in effect.
      def path_template(template = nil)
        return declare_path_template(template.to_s) if template

        @path_template || (superclass.path_template if superclass.respond_to?(:path_template))
      end

      # True for a resource that lives under a parent: one that declares
      # (or inherits) a path_template.
      def nested?
        path_template.present?
      end

      # The template's token names, in order.
      def path_params
        path_template_segments.grep(Symbol)
      end

      # The template as literal Strings and token Symbols.
      def path_template_segments
        return @path_template_segments if @path_template

        superclass.respond_to?(:path_template_segments) ? superclass.path_template_segments : []
      end

      # Splits keywords into [path values, parent, everything else]. A class
      # with no template takes no path keywords, so all of them are "else".
      def partition_path_keywords(keywords)
        return [{}, nil, keywords] unless nested?

        tokens = path_params
        [keywords.slice(*tokens), keywords[:parent], keywords.except(*tokens, :parent)]
      end

      # As partition_path_keywords, for methods whose keywords are all path
      # context: anything left over is an unknown keyword.
      def path_context!(keywords)
        path_params, parent, rest = partition_path_keywords(keywords)
        reject_unknown_keywords!(rest)
        [path_params, parent]
      end

      def reject_unknown_keywords!(keywords)
        return if keywords.empty?

        raise ArgumentError, "unknown keyword#{'s' if keywords.size > 1}: #{keywords.keys.map(&:inspect).join(', ')}"
      end

      def action_path_context(path_params, parent)
        nested? ? { path_params:, parent: } : {}
      end

      # Gives objects this class built (one, or a list of them) the path
      # values and parent of the call that produced them.
      def apply_path_context(result, path_params, parent)
        return result unless nested?

        items = result.is_a?(::Array) ? result : [result]
        items.each { |item| item.assign_path_context(path_params, parent) if item.is_a?(self) }
        result
      end

      private

      # The encoded path segments that precede the id.
      def resource_segments(path_params)
        reject_unknown_keywords!(path_params.except(*self.path_params))
        return [Resteze::Util.encode_path_segment(resource_slug)] unless nested?

        path_template_segments.map do |segment|
          next segment unless segment.is_a?(Symbol)

          Resteze::Util.encode_path_segment(path_value!(segment, path_params[segment]))
        end
      end

      # A value must be present and must not be a dot segment, which a URL
      # resolves as "this directory" or "up one" and so would leave the
      # template's path.
      def path_value!(token, value)
        return value if value.present? && !DOT_SEGMENTS.include?(value.to_s)

        raise api_module::InvalidRequestError.new(
          "Could not determine which PATH to request: #{self} needs #{token}, got #{value.inspect}", token.to_s
        )
      end

      def declare_path_template(template)
        segments = parse_path_template(template)
        tokens   = segments.grep(Symbol)
        validate_path_tokens!(template, tokens)

        @path_template = template
        @path_template_segments = segments.freeze
        define_path_readers(tokens)
        nil
      end

      def parse_path_template(template)
        template.split("/").reject(&:blank?).map do |segment|
          next segment unless segment.include?(":")

          token = segment[TOKEN, 1] or
            raise ArgumentError, "Invalid path_template segment #{segment.inspect}: a :token must be a whole " \
                                 "segment named like a method (#{template.inspect})"
          token.to_sym
        end
      end

      def validate_path_tokens!(template, tokens)
        raise ArgumentError, "path_template #{template.inspect} has no :tokens; set resource_slug instead" if tokens.empty?
        raise ArgumentError, "path_template #{template.inspect} repeats a token" if tokens.uniq.size != tokens.size

        reserved = tokens & RESERVED
        raise ArgumentError, "path_template token :#{reserved.first} is reserved" if reserved.any?

        clash = tokens.find { |token| shadows_method?(token) }
        return unless clash

        raise ArgumentError, "path_template token :#{clash} would shadow #{self}##{clash}; choose another name"
      end

      # True when a reader for the token would hide a method that is neither
      # a declared property nor a reader an ancestor's template generated.
      def shadows_method?(name)
        return false if property?(name)
        return false unless method_defined?(name) || private_method_defined?(name)

        !instance_method(name).owner.is_a?(Readers)
      end

      def define_path_readers(tokens)
        readers = Readers.new
        tokens.reject { |token| property?(token) }.each do |token|
          readers.define_method(token) { routing_path_params[token] }
        end
        readers.define_method(:parent) { path_parent } unless shadows_method?(:parent)
        include readers
      end
    end
  end
end
