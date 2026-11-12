module Resteze
  module Testing
    module Minitest
      module Object
        include ActiveSupport::Concern

        ACTION_READERS = { method: :http_method, on: :on, id: :id, id_param: :id_param,
                           returns: :returns, as: :generated_name }.freeze

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

        # Assert that an action is declared, optionally checking its resolved
        # options. `path:` is compared against the full routed path, using the
        # id "ID" for member actions.
        # rubocop:disable-next Naming/PredicatePrefix
        def has_action(name, **options)
          action = subject.actions[name.to_sym]

          assert action, "Expected #{subject} to have action: #{name}"
          assert_action_options(action, options)
        end

        def assert_action_options(action, options)
          ACTION_READERS.each do |option, reader|
            next unless options.key?(option)

            assert_equal options[option], action.public_send(reader),
                         "Expected #{subject} action #{action.name} to have #{option}: #{options[option].inspect}"
          end
          assert_action_path(action, options[:path]) if options.key?(:path)
        end

        def assert_action_path(action, path)
          actual = action.member? ? action.path_for("ID") : action.path_for

          assert_equal path, actual, "Expected #{subject} action #{action.name} to route to #{path}"
        end

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
