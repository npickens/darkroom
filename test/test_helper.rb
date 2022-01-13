# frozen_string_literal: true

require('fileutils')

module TestHelper
  ##########################################################################################################
  ## Constants                                                                                            ##
  ##########################################################################################################

  TEST_DIR = File.expand_path('..', __FILE__).freeze
  DUMMY_LIBS_DIR = File.join(TEST_DIR, 'dummy_libs').freeze
  TMP_DIR = File.join(TEST_DIR, 'tmp').freeze

  INSPECT_SPLIT = /@(?=\w+=)/.freeze
  INSPECT_JOIN = "\n@"

  MINITEST_TEST_METHOD_REGEX = /^test_/.freeze

  $:.unshift(DUMMY_LIBS_DIR)

  ##########################################################################################################
  ## Configuration                                                                                        ##
  ##########################################################################################################

  module ClassMethods
    def test(name, &block)
      define_method("#{context}#{
        if name.start_with?('self.')
          name.sub('self.', '.')
        elsif name[0] != '#'
          " #{name}"
        else
          name
        end
      }", &block)
    end

    # Override of Minitest::Runnable.methods_matching
    def methods_matching(regex)
      if regex == MINITEST_TEST_METHOD_REGEX
        public_instance_methods(true).grep(/^#{context}/).map(&:to_s)
      else
        super
      end
    end
  end

  def self.included(klass)
    klass.extend(ClassMethods)
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
end
