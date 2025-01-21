# frozen_string_literal: true

require('fileutils')
require('minitest/autorun')

module TestHelper
  TEST_DIR = __dir__.freeze
  DUMMY_LIBS_DIR = File.join(TEST_DIR, 'dummy_libs').freeze
  TMP_DIR = File.join(TEST_DIR, 'tmp').freeze

  INSPECT_SPLIT = /@(?=\w+=)/.freeze
  INSPECT_JOIN = "\n@"

  MINITEST_TEST_METHOD_REGEX = /^test_/.freeze

  @test_names = {}
  @test_numbers = {}

  class << self
    attr_accessor(:test_names)
    attr_accessor(:test_numbers)
  end

  $:.unshift(DUMMY_LIBS_DIR)

  # Run a specific test by its auto-generated number (shown in failure output). Test order is still
  # randomized, but a test's number is consistent across runs so long as tests aren't added, removed, or
  # renamed.
  #
  #   Example: bin/test 123
  #
  if ARGV[0]&.match?(/^\d+$/)
    at_exit do
      if (test_name = TestHelper.test_names[ARGV[0].to_i])
        ARGV[0] = test_name
        ARGV.unshift('-n')
      else
        abort("Test number #{ARGV[0]} doesn't exist")
      end
    end
  end

  ##########################################################################################################
  ## Testing                                                                                              ##
  ##########################################################################################################

  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods
    def context(*contexts, &block)
      contexts.each { |c| context_stack << c.to_s }
      block.call
      context_stack.pop(contexts.size)
    end

    def test(description, &block)
      method_name = "#{context_string} #{description}"
      test_methods << method_name

      if TestHelper.test_numbers.key?(method_name)
        raise("Duplicate test name: #{method_name.inspect}")
      end

      TestHelper.test_names[TestHelper.test_names.size + 1] = method_name
      TestHelper.test_numbers[method_name] = TestHelper.test_numbers.size + 1

      define_method(method_name, &block)
    end

    def context_stack
      @context_stack ||= []
    end

    def test_methods
      @test_methods ||= []
    end

    def context_string
      context_stack.each_with_object(+'').with_index do |(context, str), i|
        next_item = context_stack[i + 1]

        str << context
        str << ' ' unless !next_item || next_item[0] == '#' || next_item.start_with?('::')
      end
    end

    # Override of Minitest::Runnable.methods_matching
    def methods_matching(regex)
      regex == MINITEST_TEST_METHOD_REGEX ? test_methods : super
    end
  end

  ##########################################################################################################
  ## Hooks                                                                                                ##
  ##########################################################################################################

  def setup
    @@darkroom = nil
  end

  def teardown
    FileUtils.rm_rf(TMP_DIR)
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def write_files(files)
    files.each do |path, content|
      full_path = full_path(path)

      FileUtils.mkdir_p(File.dirname(full_path))
      File.write(full_path, content)
    end
  end

  def full_path(path)
    File.join(TMP_DIR, path)
  end

  def new_asset(path, content = nil, **options)
    write_files(path => content) if content

    @@darkroom ||= DarkroomMock.new
    asset = Darkroom::Asset.new(path, full_path(path), @@darkroom, **options)

    @@darkroom.instance_variable_get(:@manifest)[asset.path] = asset

    asset
  end

  def assert_error(*expected, actual)
    expected.flatten!
    actual = Array(actual).map { |e| "#<#{e.class}: #{e.message}>" }

    assert_equal(*[expected, actual].map { |a| "#{a.map { |l| "\n  #{l}," }.join}\n" })
  end

  def refute_error(actual)
    assert_error(actual)
  end

  def assert_inspect(expected, actual)
    assert_equal(
      expected.split(INSPECT_SPLIT).join(INSPECT_JOIN),
      actual.inspect.split(INSPECT_SPLIT).join(INSPECT_JOIN)
    )
  end

  ##########################################################################################################
  ## Mocks                                                                                                ##
  ##########################################################################################################

  class DarkroomMock
    def initialize() @manifest = {} end
    def manifest(path) @manifest[path] end
    def process_key() 1 end
  end

  ##########################################################################################################
  ## Minitest                                                                                             ##
  ##########################################################################################################

  class Minitest::Result
    def location
      super.delete_prefix("#{class_name}#").prepend("[##{TestHelper.test_numbers[self.name]}] ")
    end
  end
end
