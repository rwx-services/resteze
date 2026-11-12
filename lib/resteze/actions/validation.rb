module Resteze
  module Actions
    # Declaration-time checks for the action DSL. The declaration is resolved
    # through the lookup chain (without being stored) so scope and generated
    # name reflect inherited and module-level options, not just the options
    # given on this line.
    module Validation
      private

      # Returns the resolved candidate action, or raises ArgumentError.
      def validate_action!(name, options)
        Resteze::Action.validate_options!(name, options)
        candidate = resolve_action(name, options)
        validate_id_options!(candidate, options)
        validate_returns!(candidate, options)
        check_action_collision!(candidate) unless candidate.reserved?
        candidate
      end

      def validate_id_options!(candidate, options)
        return unless candidate.collection?
        return unless options.key?(:id) || options.key?(:id_param)

        raise ArgumentError, "id: and id_param: only apply to member actions (action :#{candidate.name})"
      end

      def validate_returns!(candidate, options)
        return unless options[:returns] == :list && !(self <= Resteze::List)

        raise ArgumentError, "returns: :list requires #{self} to include List (action :#{candidate.name})"
      end

      def check_action_collision!(candidate)
        method_name = candidate.generated_name
        return if inherited_action_method?(candidate)

        clash = respond_to?(method_name, true) ||
                (candidate.member? && (method_defined?(method_name) || private_method_defined?(method_name)))
        return unless clash

        raise ArgumentError, "action :#{candidate.name} would define #{self}.#{method_name}, which already exists; " \
                             "pass as: to choose another method name"
      end

      # True when the method this declaration would define is the one an
      # ancestor's declaration of the same action already generated, so
      # redefining it is an override, not a collision.
      def inherited_action_method?(candidate)
        action_ancestors.drop(1).any? do |klass|
          klass.declared_actions.key?(candidate.name) &&
            klass.actions[candidate.name].generated_name == candidate.generated_name
        end
      end
    end
  end
end
