# frozen_string_literal: true

module TestHelper
  ##########################################################################################################
  ## Constants                                                                                            ##
  ##########################################################################################################

  TEST_DIR = File.expand_path('..', __FILE__).freeze
  ASSET_DIR = File.join(TEST_DIR, 'assets').freeze
  BAD_ASSET_DIR = File.join(TEST_DIR, 'bad_assets').freeze
  DUMMY_LIBS_DIR = File.join(TEST_DIR, 'dummy_libs').freeze

  JS_ASSET_PATH = '/app.js'
  JS_ASSET_PATH_VERSIONED = '/app-25f290825cb44d4cf57632abfa82c37e.js'
  JS_ASSET_FILE = File.join(ASSET_DIR, JS_ASSET_PATH).freeze

  CSS_ASSET_PATH = '/app.css'
  CSS_ASSET_PATH_VERSIONED = '/app-c21dbc03fb551f55b202b56908f8e4d5.css'

  PRISTINE_ASSET_PATH = '/robots.txt'
  PRISTINE_ASSET_PATH_VERSIONED = '/robots-b6216d61c03e6ce0c9aea6ca7808f7ca.txt'

  ##########################################################################################################
  ## Configuration                                                                                        ##
  ##########################################################################################################

  $:.unshift(DUMMY_LIBS_DIR)

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
end
