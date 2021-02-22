class DarkroomTest < Minitest::Test
  ##########################################################################################################
  ## Constants                                                                                            ##
  ##########################################################################################################

  TEST_DIR = File.expand_path('..', __FILE__).freeze
  ASSET_DIR = File.join(TEST_DIR, 'assets').freeze
  DUMMY_LIBS_DIR = File.join(TEST_DIR, 'dummy_libs').freeze

  $:.unshift(DUMMY_LIBS_DIR)

  ##########################################################################################################
  ## Configuration                                                                                        ##
  ##########################################################################################################

  def self.test(name, &block)
    define_method("#{contexts.join('::')}#{
      name.start_with?('self.') ? name.sub('self.', '.') : name[0] == '#' ? '' : ' '
    }#{name}", &block)
  end

  def self.contexts
    %w[Darkroom]
  end

  def self.runnable_methods
    public_instance_methods(true).grep(/^#{contexts.first}/).map(&:to_s)
  end

  ##########################################################################################################
  ## Test #inspect                                                                                        ##
  ##########################################################################################################

  test('#inspect returns a high-level object info string') do
    darkroom = Darkroom.new(ASSET_DIR,
      hosts: 'https://cdn1.hello.world',
      prefix: '/static',
      pristine: '/hi.txt',
      minified_pattern: /\.minified\.*/,
      internal_pattern: /^\/private\//,
      min_process_interval: 1,
    )
    darkroom.process

    assert_equal('#<Darkroom: '\
      '@errors=['\
        '#<Darkroom::AssetNotFoundError: Asset not found (referenced from /bad-import.js:1): '\
          '/does-not-exist.js>, '\
        '#<Darkroom::AssetNotFoundError: Asset not found (referenced from /bad-imports.js:1): '\
          '/does-not-exist.js>, '\
        '#<Darkroom::AssetNotFoundError: Asset not found (referenced from /bad-imports.js:2): '\
          '/also-does-not-exist.js>'\
      '], '\
      "@globs={\"#{ASSET_DIR}\"=>\"#{ASSET_DIR}/**/*{#{Darkroom::Asset.extensions.join(',')}}\"}, "\
      '@hosts=["https://cdn1.hello.world"], '\
      '@internal_pattern=/^\\/private\\//, '\
      "@last_processed_at=#{darkroom.instance_variable_get(:@last_processed_at)}, "\
      '@min_process_interval=1, '\
      '@minified_pattern=/\\.minified\\.*/, '\
      '@minify=false, '\
      '@prefix="/static", '\
      '@pristine=#<Set: {"/favicon.ico", "/mask-icon.svg", "/humans.txt", "/robots.txt", "/hi.txt"}>'\
    '>'.split(', @').join(",\n@"), darkroom.inspect.split(', @').join(",\n@"))
  end
end
