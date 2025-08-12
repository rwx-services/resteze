module Resteze
  module ApiModule
    extend ActiveSupport::Concern

    delegate :api_module, :logger, :util, to: :class

    module ClassMethods
      def api_module
        @api_module ||=
          begin
            parents = name.scan("::").inject([name]) { |mods, _n| mods << mods.last.deconstantize }
            parents.map(&:constantize).detect { |mod| mod == Resteze || mod.include?(Resteze) }
          end
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
