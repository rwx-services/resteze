module Resteze
  # The action routing DSL for resources. Each class stores only its own
  # declarations; resolution walks the chain lazily on every lookup:
  # REST built-ins, module action_defaults, module declarations, ancestor
  # classes (farthest first), then this class.
  module Actions
    extend ActiveSupport::Concern

    module ClassMethods
      include Resteze::Actions::Validation

      def action(name, **options)
        name = name.to_sym
        candidate = validate_action!(name, options)
        declared_actions[name] = options
        define_action_methods(candidate) unless candidate.reserved?
        nil
      end

      def declared_actions
        @declared_actions ||= {}
      end

      def actions
        action_names.to_h { |name| [name, resolve_action(name)] }.freeze
      end

      # Override to transform params before an action request is sent.
      def action_params(_name, params)
        params
      end

      # Override to supply headers for an action request.
      def action_headers(_name, _params)
        {}
      end

      def invoke_action(name, params = {}, id: nil)
        action = actions.fetch(name)
        raise_invalid_action_id!(id) if action.member? && id.blank?

        params = action_params(name, params)
        params = { action.id_param => id }.merge(params) if action.member? && action.id == :param
        response = request(action.http_method, action.path_for(id), params:, headers: action_headers(name, params))
        build_action_result(action, response)
      end

      private

      def action_names
        (Resteze::Action::RESERVED + action_ancestors.flat_map { |klass| klass.declared_actions.keys }).uniq
      end

      # Classes in the ancestry that hold declarations, nearest first.
      def action_ancestors
        ancestors.select { |ancestor| ancestor.is_a?(Class) && ancestor.respond_to?(:declared_actions) }
      end

      # Resolves one action through the full chain. `own` stands in for this
      # class's stored declaration, so a declaration can be resolved before it
      # is stored.
      def resolve_action(name, own = declared_actions.fetch(name, {}))
        options = Resteze::Action::BUILT_IN.fetch(name, {}).merge(api_module.action_defaults)
        options.merge!(api_module.action_declarations.fetch(name, {}))
        action_ancestors.drop(1).reverse_each { |klass| options.merge!(klass.declared_actions.fetch(name, {})) }
        Resteze::Action.new(name, self, options.merge(own))
      end

      def raise_invalid_action_id!(id)
        raise api_module::InvalidRequestError.new(
          "Could not determine which PATH to request: #{self} instance has invalid ID: #{id.inspect}", "id"
        )
      end

      def build_action_result(action, response)
        case action.returns
        when nil   then api_module::Result.from_response(response)
        when :self then convert_action_data(response.data, self)
        when :list then construct_list_from(response.data)
        when Class then convert_action_data(response.data, action.returns)
        else raise ArgumentError, "Unsupported returns: #{action.returns.inspect} (action :#{action.name})"
        end
      end

      # A Hash is an envelope (object_key is unwrapped, as in #refresh); an
      # Array holds bare items (each is wrapped, as in ListObject).
      def convert_action_data(data, klass)
        case data
        when Hash  then klass.construct_from(data)
        when Array then util.convert_to_object(data, klass)
        else data
        end
      end

      def define_action_methods(action)
        name = action.name
        method_name = action.generated_name
        if action.member?
          define_method(method_name) { |**params| self.class.invoke_action(name, params, id:) }
          define_singleton_method(method_name) { |id, **params| new(id).public_send(method_name, **params) }
        else
          define_singleton_method(method_name) { |**params| invoke_action(name, params) }
        end
      end
    end
  end
end
