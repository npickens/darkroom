module TestHelper
  ##########################################################################################################
  ## Constants                                                                                            ##
  ##########################################################################################################

  TEST_DIR = File.expand_path('..', __FILE__).freeze
  ASSET_DIR = File.join(TEST_DIR, 'assets').freeze
  DUMMY_LIBS_DIR = File.join(TEST_DIR, 'dummy_libs').freeze

  JS_ASSET_PATH = '/app.js'
  JS_ASSET_FILE = File.join(ASSET_DIR, JS_ASSET_PATH).freeze

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

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def get_asset(*args, **options)
    path = args.first.kind_of?(String) ? args.first : JS_ASSET_PATH
    file = file_for(path)
    manifest = args.last.kind_of?(Hash) ? args.last : {}

    Darkroom::Asset.new(path, file, manifest, **options)
  end

  def file_for(path)
    File.join(ASSET_DIR, path)
  end
end
