module Resteze
  module Testing
    module Configuration
      # Assert that a config property can be assigned and reads back the
      # assigned value. The original value is restored afterwards.
      def assert_config_property(property, value = nil, subject: nil)
        subject ||= (defined?(@subject) && @subject) || self.subject
        original_value = subject.send(property)
        subject.send("#{property}=", value)

        expect(subject.send(property)).to eq(value), "config property #{property} value did not match expectation"
      ensure
        # Make sure to set the original value at the end
        subject.send("#{property}=", original_value)
      end
    end
  end
end
