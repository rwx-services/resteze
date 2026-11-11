module Resteze
  module Testing
    module RSpec
      module Object
        extend RSpec::Matchers

        ACTION_READERS = { method: :http_method, on: :on, id: :id, id_param: :id_param,
                           returns: :returns, as: :generated_name }.freeze

        # rubocop:disable Metrics/AbcSize
        # rubocop:disable-next Naming/PredicatePrefix
        def has_property(name, **options)
          expect(subject.property?(name.to_sym)).to be(true), "Expected #{subject} to have property: #{name}"
          assert_property_default(name, options[:default]) if options.key?(:default)
          assert_property_translation(name, options[:from]) if options.key?(:from)
          assert_property_transformed(name, transformed: options[:transformed]) if options.key?(:transformed)
          assert_property_required(name, required: options[:required]) if options.key?(:required)
        end

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

        # Assert that an action is declared, optionally checking its resolved
        # options. `path:` is compared against the full routed path, using the
        # id "ID" for member actions.
        # rubocop:disable-next Naming/PredicatePrefix
        def has_action(name, **options)
          action = subject.actions[name.to_sym]

          expect(action).not_to be_nil, "Expected #{subject} to have action: #{name}"
          assert_action_options(action, options)
        end

        def assert_action_options(action, options)
          ACTION_READERS.each do |option, reader|
            next unless options.key?(option)

            expect(action.public_send(reader)).to eq(options[option]),
                                                  "Expected #{subject} action #{action.name} to have #{option}: " \
                                                  "#{options[option].inspect}"
          end
          assert_action_path(action, options[:path]) if options.key?(:path)
        end

        def assert_action_path(action, path)
          actual = action.member? ? action.path_for("ID") : action.path_for

          expect(actual).to eq(path), "Expected #{subject} action #{action.name} to route to #{path}"
        end

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
