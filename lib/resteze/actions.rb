module Resteze
  # The action routing DSL for resources. Each class stores only its own
  # declarations; resolution walks the chain lazily on every lookup:
  # REST built-ins, module action_defaults, module declarations, ancestor
  # classes (farthest first), then this class.
  module Actions
    extend ActiveSupport::Concern

    module ClassMethods
      def action(name, **options)
        name = name.to_sym
        validate_action_options!(name, options)
        declared_actions[name] = options
        nil
      end

      def declared_actions
        @declared_actions ||= {}
      end

      def actions
        action_names.to_h { |name| [name, resolve_action(name)] }.freeze
      end

      private

      def action_names
        (Resteze::Action::RESERVED + action_ancestors.flat_map { |klass| klass.declared_actions.keys }).uniq
      end

      # Classes in the ancestry that hold declarations, nearest first.
      def action_ancestors
        ancestors.select { |ancestor| ancestor.is_a?(Class) && ancestor.respond_to?(:declared_actions) }
      end

      def resolve_action(name)
        options = Resteze::Action::BUILT_IN.fetch(name, {}).merge(api_module.action_defaults)
        options.merge!(api_module.action_declarations.fetch(name, {}))
        action_ancestors.reverse_each { |klass| options.merge!(klass.declared_actions.fetch(name, {})) }
        Resteze::Action.new(name, self, options)
      end

      def validate_action_options!(name, options)
        validate_option_keys!(options)
        validate_reserved_scope!(name, options)
        validate_id_options!(name, options)
        validate_returns!(name, options)
      end

      def validate_option_keys!(options)
        unknown = options.keys - Resteze::Action::OPTIONS
        raise ArgumentError, "Unknown action option(s): #{unknown.join(', ')}" if unknown.any?
      end

      def validate_reserved_scope!(name, options)
        return unless Resteze::Action::RESERVED.include?(name) && options.key?(:on)

        raise ArgumentError, "on: cannot be changed for the built-in action :#{name}"
      end

      def validate_id_options!(name, options)
        return unless declaration_scope(name, options) == :collection
        return unless options.key?(:id) || options.key?(:id_param)

        raise ArgumentError, "id: and id_param: only apply to member actions (action :#{name})"
      end

      def validate_returns!(name, options)
        return unless options[:returns] == :list && !(self <= Resteze::List)

        raise ArgumentError, "returns: :list requires #{self} to include List (action :#{name})"
      end

      def declaration_scope(name, options)
        options[:on] ||
          api_module.action_declarations.dig(name, :on) ||
          Resteze::Action::BUILT_IN.dig(name, :on) ||
          :collection
      end
    end
  end
end
