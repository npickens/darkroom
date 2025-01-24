# frozen_string_literal: true

require('fileutils')
require('minitest/autorun')
require('minitest/reporters')

module Minitest
  def self.plugin_index_init(options)
    return unless options[:filter].to_i.to_s == options[:filter]

    options[:filter] = "/^test_#{options[:filter]}: /"
  end

  register_plugin('index')

  Reporters.use!(Reporters::ProgressReporter.new)
end

module TestHelper
  TEST_DIR = __dir__.freeze
  DUMMY_LIBS_DIR = File.join(TEST_DIR, 'dummy_libs').freeze
  TMP_DIR = File.join(TEST_DIR, 'tmp').freeze

  INSPECT_SPLIT = /@(?=\w+=)/.freeze
  INSPECT_JOIN = "\n@"

  $LOAD_PATH.unshift(DUMMY_LIBS_DIR)

  ##########################################################################################################
  ## Testing                                                                                              ##
  ##########################################################################################################

  def self.included(klass)
    klass.extend(ClassMethods)
  end

  module ClassMethods
    def test(description, &block)
      @@test_count ||= 0
      @@test_count += 1

      method_name =
        "test_#{@@test_count}: " \
        "#{name.chomp('Test') unless description.match?(/^[A-Z]/)}" \
        "#{' ' unless description.match?(/^[A-Z#.]/)}" \
        "#{description}"

      define_method(method_name, &block)
    end
  end

  ##########################################################################################################
  ## Hooks                                                                                                ##
  ##########################################################################################################

  def setup
    @darkroom = nil
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

    @darkroom ||= DarkroomMock.new
    asset = Darkroom::Asset.new(path, full_path(path), @darkroom, **options)

    @darkroom.instance_variable_get(:@manifest)[asset.path] = asset

    asset
  end

  def assert_error(*expected, actual)
    expected = expected.flatten.join("\n")
    actual = Array(actual).map { |e| "#<#{e.class}: #{e.message}>" }.join("\n")

    assert_equal(expected, actual)
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
    def initialize
      @manifest = {}
    end

    def manifest(path)
      @manifest[path]
    end

    def process_key
      1
    end
  end
end
