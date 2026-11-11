module Resteze
  module Actions
    # Declaration-time checks for the action DSL. Everything here depends only
    # on the declaring class and its options, never on the lazy lookup chain.
    module Validation
      private

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

      def check_action_collision!(name, options)
        method_name = (options[:as] || name).to_sym
        member = declaration_scope(name, options) == :member
        clash = respond_to?(method_name, true) ||
                (member && (method_defined?(method_name) || private_method_defined?(method_name)))
        return unless clash

        raise ArgumentError, "action :#{name} would define #{self}.#{method_name}, which already exists; " \
                             "pass as: to choose another method name"
      end

      # The scope an action is declared with, resolved at declaration time so
      # the right methods can be generated: own option, module declaration,
      # built-in default, else :collection.
      def declaration_scope(name, options)
        options[:on] ||
          api_module.action_declarations.dig(name, :on) ||
          Resteze::Action::BUILT_IN.dig(name, :on) ||
          :collection
      end
    end
  end
end
