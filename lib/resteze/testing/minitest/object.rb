module Resteze
  module Testing
    module Minitest
      module Object
        include ActiveSupport::Concern

        private

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Naming/PredicatePrefix
        def has_property(name, **options)
          assert subject.property?(name.to_sym), "Expected #{subject} to have property: #{name}"
          assert_property_default(name, options[:default]) if options.key?(:default)
          assert_property_translation(name, options[:from]) if options.key?(:from)
          assert_property_transformed(name, transformed: options[:transformed]) if options.key?(:transformed)
          assert_property_required(name, required: options[:required]) if options.key?(:required)
        end
        # rubocop:enable Metrics/AbcSize
        # rubocop:enable Naming/PredicatePrefix

        def assert_property_transformed(name, transformed: true)
          translation = subject.translations_hash.dig(subject.translations.key(name.to_sym), name.to_sym)
          transformation_defined = translation.is_a?(Proc) || subject.transformation_exists?(name.to_sym)

          if transformed
            assert transformation_defined, "Expected #{subject} to transform property: #{name}"
          else
            refute transformation_defined, "Expected #{subject} not to transform property: #{name}"
          end
        end

        def assert_property_required(name, required: true)
          if required
            assert subject.required?(name.to_sym), "Expected #{subject} to require property: #{name}"
          else
            refute subject.required?(name.to_sym), "Expected #{subject} not to require property: #{name}"
          end
        end

        def assert_property_translation(name, from)
          assert_equal(
            from.to_sym,
            subject.translations.key(name.to_sym),
            "Expected #{subject} to map property #{name} from #{from}"
          )
        end

        def assert_property_default(name, default)
          assert_equal(
            default,
            subject.defaults[name.to_sym],
            "Expected #{subject} to have default for property #{name}"
          )
        end
      end
    end
  end
end
