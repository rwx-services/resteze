module Resteze
  module Testing
    module Configuration
      extend ActiveSupport::Concern

      # Assert that a config property is supported and can be assigned
      def assert_config_property(property, value = nil, subject: nil)
        subject ||= (defined?(@subject) && @subject) || subject()
        original_value = subject.send(property)

        assert_equal value, subject.send(property), "config property #{property} value did not match expectation"
      ensure
        # Make sure to set the original value at the end
        subject.send("#{property}=", original_value)
      end
    end
  end
end
