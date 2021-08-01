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

  $:.unshift(DUMMY_LIBS_DIR)

  ##########################################################################################################
  ## Configuration                                                                                        ##
  ##########################################################################################################

  module ClassMethods
    def test(name, &block)
      define_method("#{context}#{
        name.start_with?('self.') ? name.sub('self.', '.') : name[0] == '#' ? '' : ' '
      }#{name}", &block)
    end

    # Override of Minitest::Test.runnable_methods
    def runnable_methods
      public_instance_methods(true).grep(/^#{context}/).map(&:to_s)
    end
  end

  def self.included(klass)
    klass.extend(ClassMethods)
  end

  ##########################################################################################################
  ## Hooks                                                                                                ##
  ##########################################################################################################

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
end
