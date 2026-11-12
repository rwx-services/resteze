module Resteze
  module ApiModule
    extend ActiveSupport::Concern

    delegate :api_module, :logger, :util, to: :class

    module ClassMethods
      def api_module
        @api_module ||= name.nil? ? inherited_api_module : named_api_module
      end

      # An anonymous subclass belongs where its parent does.
      def inherited_api_module
        superclass.api_module if respond_to?(:superclass) && superclass.respond_to?(:api_module)
      end

      def named_api_module
        parents = name.scan("::").inject([name]) { |mods, _n| mods << mods.last.deconstantize }
        parents.map(&:constantize).detect { |mod| mod == Resteze || mod.include?(Resteze) }
      end

      def logger
        api_module.logger
      end

      def util
        api_module::Util
      end
    end
  end
end
