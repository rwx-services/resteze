module Resteze
  module Testing
    module RSpec
      module Object
        extend RSpec::Matchers

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable Naming/PredicatePrefix
        def has_property(name, **options)
          expect(subject.property?(name.to_sym)).to be(true), "Expected #{subject} to have property: #{name}"
          assert_property_default(name, options[:default]) if options.key?(:default)
          assert_property_translation(name, options[:from]) if options.key?(:from)
          assert_property_transformed(name, transformed: options[:transformed]) if options.key?(:transformed)
          assert_property_required(name, required: options[:required]) if options.key?(:required)
        end
        # rubocop:enable Naming/PredicatePrefix

        def assert_property_transformed(name, transformed: true)
          translation = subject.translations_hash.dig(subject.translations.key(name.to_sym), name.to_sym)
          transformation_defined = translation.is_a?(Proc) || subject.transformation_exists?(name.to_sym)

          if transformed
            expect(transformation_defined).to be(true), "Expected #{subject} to transform property: #{name}"
          else
            expect(transformation_defined).to be(false), "Expected #{subject} not to transform property: #{name}"
          end
        end
        # rubocop:enable Metrics/AbcSize

        def assert_property_required(name, required: true)
          if required
            expect(subject.required?(name.to_sym)).to be(true), "Expected #{subject} to require property: #{name}"
          else
            expect(subject.required?(name.to_sym)).to be(false), "Expected #{subject} not to require property: #{name}"
          end
        end

        def assert_property_translation(name, from)
          expect(subject.translations.key(name.to_sym)).to eq(from.to_sym),
                                                           "Expected #{subject} to map property #{name} from #{from}"
        end

        def assert_property_default(name, default)
          expect(subject.defaults[name.to_sym]).to eq(default), "Expected #{subject} to have default for property #{name}"
        end
      end
    end
  end
end
