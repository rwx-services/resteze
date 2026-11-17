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

      # Resolves one action by name. The built-ins and generated methods go
      # through this rather than #actions, so a consumer who already defines
      # a class method named `actions` is unaffected.
      def action_for(name)
        name = name.to_sym
        raise KeyError, "#{self} has no action :#{name}" unless action_names.include?(name)

        resolve_action(name)
      end

      # Override to transform params before an action request is sent.
      def action_params(_name, params)
        params
      end

      # Override to supply headers for an action request.
      def action_headers(_name, _params)
        {}
      end

      # path_params and parent are the path context of a class that declares
      # a path_template; they route the request and are handed to any of
      # this class's objects in the result. Other classes are never passed
      # them.
      def invoke_action(name, params = {}, id: nil, path_params: {}, parent: nil)
        action = action_for(name)
        raise_invalid_action_id!(id) if action.member? && id.blank?

        response = request_action(action, action_params(name, params), id, path_params)
        apply_path_context(build_action_result(action, response), path_params, parent)
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

      def request_action(action, params, id, path_params)
        params = { action.id_param => id }.merge(params) if action.member? && action.id == :param
        request(action.http_method, action.path_for(id, path_params), params:,
                                                                      headers: action_headers(action.name, params))
      end

      def define_action_methods(action)
        action.member? ? define_member_action(action) : define_collection_action(action)
      end

      # The instance form routes with the instance's own path context, so
      # every keyword is a request param; the class form takes path context
      # from its keywords.
      def define_member_action(action)
        name = action.name
        method_name = action.generated_name
        define_method(method_name) do |**params|
          self.class.invoke_action(name, params, id:, **action_path_context)
        end
        define_singleton_method(method_name) do |id, **params|
          path_params, parent, params = partition_path_keywords(params)
          new(id).assign_path_context(path_params, parent).public_send(method_name, **params)
        end
      end

      def define_collection_action(action)
        name = action.name
        define_singleton_method(action.generated_name) do |**params|
          path_params, parent, params = partition_path_keywords(params)
          invoke_action(name, params, **action_path_context(path_params, parent))
        end
      end
    end
  end
end
