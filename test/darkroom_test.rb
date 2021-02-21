class DarkroomTest < Minitest::Spec
  ##########################################################################################################
  ## Constants                                                                                            ##
  ##########################################################################################################

  TEST_DIR = File.expand_path('..', __FILE__).freeze
  ASSET_DIR = File.join(TEST_DIR, 'assets').freeze
  DUMMY_LIBS_DIR = File.join(TEST_DIR, 'dummy_libs').freeze

  $:.unshift(DUMMY_LIBS_DIR)

  ##########################################################################################################
  ## Tests                                                                                                ##
  ##########################################################################################################

  describe('Darkroom') do
    ########################################################################################################
    ## Darkroom#inspect                                                                                   ##
    ########################################################################################################

    describe('#inspect') do
      it('returns a high-level object info string') do
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
  end
end
