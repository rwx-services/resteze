require "test_helper"
require "open3"
require "rbconfig"

# The documentation is what people and coding agents copy from, so it is held
# to what the gem actually provides: every Ruby example parses, every file it
# tells you to require loads, and every Resteze constant and mixin it names
# exists.
class DocsTest < Minitest::Spec
  ROOT  = File.expand_path("..", __dir__)
  FILES = ["README.md", "AGENTS.md", *Dir[File.join(ROOT, "docs", "*.md")].map { |path| path.delete_prefix("#{ROOT}/") }]
          .select { |path| File.exist?(File.join(ROOT, path)) }.freeze

  # Mixins that examples define for themselves rather than get from Resteze.
  LOCAL_MIXINS = %w[ApiTestHelpers].freeze

  def self.text(path)
    File.read(File.join(ROOT, path))
  end

  def self.ruby_blocks(path)
    text(path).scan(/^```ruby\n(.*?)^```/m).flatten
  end

  # Runs a script in a fresh interpreter: loading the RSpec helpers here would
  # replace the Minitest ones this suite uses.
  def run_ruby(script)
    Open3.capture2e(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", script)
  end

  FILES.each do |path|
    describe path do
      it "has only Ruby examples that parse" do
        DocsTest.ruby_blocks(path).each_with_index do |code, index|
          RubyVM::InstructionSequence.compile(code)
        rescue SyntaxError => e
          flunk "#{path}, Ruby example #{index + 1} does not parse: #{e.message.lines.first}"
        end
      end

      it "includes only mixins that Resteze provides" do
        names = DocsTest.ruby_blocks(path).join.scan(/^\s*include ((?:[A-Z]\w*Api::)?[A-Z]\w*)$/).flatten
        names = names.map { |name| name.split("::").last }.uniq - LOCAL_MIXINS - ["Resteze"]
        missing = names.reject { |name| Resteze.const_defined?(name, false) }

        assert_empty missing, "#{path} includes #{missing.join(', ')}, which Resteze does not define"
      end
    end
  end

  it "requires only files that load" do
    paths = FILES.flat_map { |path| DocsTest.text(path).scan(/require ['"](resteze[^'"]*)['"]/) }.flatten.uniq

    paths.each do |path|
      output, status = run_ruby(%(require "rspec/expectations"; require "resteze"; require "#{path}"))

      assert_predicate status, :success?, "require #{path.inspect} failed:\n#{output}"
    end
  end

  it "names only Resteze constants that exist" do
    names = FILES.flat_map { |path| DocsTest.text(path).scan(/\bResteze::[A-Z]\w*(?:::[A-Z]\w*)*/) }.uniq.sort
    script = <<~RUBY
      require "rspec/expectations"
      require "resteze"
      require "resteze/testing/minitest"
      require "resteze/testing/rspec"
      puts #{names.inspect}.reject { |name| Object.const_defined?(name) }
    RUBY
    output, status = run_ruby(script)

    assert_predicate status, :success?, output
    assert_empty output.split("\n"), "The docs name constants that do not exist"
  end
end
