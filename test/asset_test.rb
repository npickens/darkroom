class AssetTest < Minitest::Test
  describe('Darkroom') do
    describe('Asset') do
      ######################################################################################################
      ## Setup                                                                                            ##
      ######################################################################################################

      begin
        TEST_DIR = File.expand_path('..', __FILE__).freeze
        ASSET_DIR = File.join(TEST_DIR, 'assets').freeze
        DUMMY_LIBS_DIR = File.join(TEST_DIR, 'dummy_libs').freeze

        JS_ASSET_PATH = '/app.js'
        JS_ASSET_FILE = File.join(ASSET_DIR, JS_ASSET_PATH)

        $:.unshift(DUMMY_LIBS_DIR)

        def get_asset(*args, **options)
          path = args[0] || JS_ASSET_PATH
          file = args[1] || file_for(path)
          manifest = args[2] || {}

          Darkroom::Asset.new(path, file, manifest, **options)
        end

        def file_for(path)
          File.join(ASSET_DIR, path)
        end
      end

      ######################################################################################################
      ## Asset#initialize                                                                                 ##
      ######################################################################################################

      describe('#initialize') do
        it('raises SpecNotDefinedError if no spec is defined for a file extension') do
          path = '/app.undefined'
          file = file_for(path)

          error = assert_raises(Darkroom::SpecNotDefinedError) do
            get_asset(path)
          end

          assert_includes(error.inspect, '.undefined')
          assert_includes(error.inspect, file)
        end

        it('requires compile library if spec has one') do
          Darkroom::Asset.add_spec('.dummy-compile', 'text/dummy-compile',
            compile_lib: 'dummy_compile',
            compile: -> (path, content) { DummyCompile.compile(path, content) },
          )

          refute(defined?(DummyCompile), 'Expected DummyCompile to be undefined when an asset of that '\
            'type has not be initialized yet.')

          get_asset('/app.dummy-compile')

          assert(defined?(DummyCompile), 'Expected DummyCompile to be defined.')
        end

        it('requires minify library if spec has one and minification is enabled') do
          Darkroom::Asset.add_spec('.dummy-minify', 'text/dummy-minify',
            minify: -> (content) { DummyMinify.minify(content) },
            minify_lib: 'dummy_minify',
          )

          get_asset('/app.dummy-minify')
          refute(defined?(DummyMinify), 'Expected DummyMinify to be undefined when minification is not '\
            'enabled.')

          get_asset('/app.dummy-minify', minify: true)
          assert(defined?(DummyMinify), 'Expected DummyMinify to be defined.')
        end

        it('raises MissingLibraryError if compile library is not available') do
          Darkroom::Asset.add_spec('.bad-compile', 'text/bad-compile', compile_lib: 'bad_compile')

          error = assert_raises(Darkroom::MissingLibraryError) do
            get_asset('/app.bad-compile')
          end

          assert_includes(error.inspect, Darkroom::Asset.spec('.bad-compile').compile_lib)
        ensure
          Darkroom::Asset.class_variable_get(:@@specs).delete('.bad-compile')
        end

        it('raises MissingLibraryError if minify library is not available and minification is enabled') do
          Darkroom::Asset.add_spec('.bad-minify', 'text/bad-minify', minify_lib: 'bad_minify')

          begin
            get_asset('/app.bad-minify')
          rescue Darkroom::MissingLibraryError => e
            assert(false, 'Expected minify library to not be required when minification is not enabled')
          end

          error = assert_raises(Darkroom::MissingLibraryError) do
            get_asset('/app.bad-minify', minify: true)
          end

          assert_includes(error.inspect, Darkroom::Asset.spec('.bad-minify').minify_lib)
        ensure
          Darkroom::Asset.class_variable_get(:@@specs).delete('.bad-minify')
        end
      end

      ######################################################################################################
      ## Asset#content_type                                                                               ##
      ######################################################################################################

      describe('#content_type') do
        it('returns the HTTP MIME type string for the asset') do
          assert_equal('text/css', get_asset('/app.css').content_type)
          assert_equal('text/html', get_asset('/index.html').content_type)
          assert_equal('application/javascript', get_asset('/template.htx').content_type)
          assert_equal('image/x-icon', get_asset('/favicon.ico').content_type)
          assert_equal('application/javascript', get_asset('/app.js').content_type)
          assert_equal('image/jpeg', get_asset('/photo.jpg').content_type)
          assert_equal('image/png', get_asset('/graphic.png').content_type)
          assert_equal('image/svg+xml', get_asset('/graphic.svg').content_type)
          assert_equal('text/plain', get_asset('/robots.txt').content_type)
          assert_equal('font/woff', get_asset('/font.woff').content_type)
          assert_equal('font/woff2', get_asset('/font.woff2').content_type)
        end
      end

      ######################################################################################################
      ## Asset#headers                                                                                    ##
      ######################################################################################################

      describe('#headers') do
        it('includes Content-Type header') do
          Darkroom::Asset.extensions.each do |extension|
            asset = get_asset("/hello#{extension}")
            assert_equal(asset.content_type, asset.headers['Content-Type'])
          end
        end

        it('includes Cache-Control header if :versioned is not specified') do
          asset = get_asset
          headers = asset.headers

          assert_equal('public, max-age=31536000', headers['Cache-Control'])
          assert_nil(headers['ETag'])
        end

        it('includes Cache-Control header if :versioned is true') do
          asset = get_asset
          asset.process(Time.now.to_f)

          headers = asset.headers(versioned: true)

          assert_equal('public, max-age=31536000', headers['Cache-Control'])
          assert_nil(headers['ETag'])
        end

        it('includes ETag header if :versioned is false') do
          asset = get_asset
          asset.process(Time.now.to_f)

          headers = asset.headers(versioned: false)

          assert_equal('"25f290825cb44d4cf57632abfa82c37e"', headers['ETag'])
          assert_nil(headers['Cache-Control'])
        end
      end

      ######################################################################################################
      ## Asset#internal?                                                                                  ##
      ######################################################################################################

      describe('#internal?') do
        it('returns true if asset was initialized as internal') do
          asset = get_asset(internal: true)

          assert(asset.internal?)
        end

        it('returns false if asset was initialized as non-internal') do
          asset = get_asset(internal: false)

          refute(asset.internal?)
        end

        it('returns false if asset was initialized without specifying internal status') do
          asset = get_asset

          refute(asset.internal?)
        end
      end

      ######################################################################################################
      ## Asset#error                                                                                      ##
      ######################################################################################################

      describe('#error') do
        it('returns nil if there were no errors during processing') do
          asset = get_asset
          asset.process(Time.now.to_f)

          assert_nil(asset.error)
        end

        it('returns ProcessingError instance if there were one or more errors during processing') do
          asset = get_asset('/bad-imports.js')
          asset.process(Time.now.to_f)

          assert_instance_of(Darkroom::ProcessingError, asset.error)
          assert_equal(2, asset.error.size)

          assert_instance_of(Darkroom::AssetNotFoundError, asset.errors.first)
          assert_includes(asset.error.inspect, asset.errors.first.to_s)
          assert_includes(asset.error.first.inspect, '/does-not-exist.js')

          assert_instance_of(Darkroom::AssetNotFoundError, asset.errors.last)
          assert_includes(asset.error.inspect, asset.errors.last.to_s)
          assert_includes(asset.error.last.inspect, '/also-does-not-exist.js')
        end
      end

      ######################################################################################################
      ## Asset#errors                                                                                     ##
      ######################################################################################################

      describe('#errors') do
        it('returns empty array if there were no errors during processing') do
          asset = get_asset
          asset.process(Time.now.to_f)

          assert_empty(asset.errors)
        end

        it('returns array of errors if there were one or more errors during processing') do
          asset = get_asset('/bad-imports.js')
          asset.process(Time.now.to_f)

          assert_instance_of(Array, asset.errors)
          assert_equal(2, asset.errors.size)

          assert_instance_of(Darkroom::AssetNotFoundError, asset.errors.first)
          assert_includes(asset.errors.inspect, asset.errors.first.inspect)

          assert_instance_of(Darkroom::AssetNotFoundError, asset.errors.last)
          assert_includes(asset.errors.inspect, asset.errors.last.inspect)
        end
      end

      ######################################################################################################
      ## Asset#error?                                                                                     ##
      ######################################################################################################

      describe('#error?') do
        it('returns true if there were one or more errors during processing') do
          asset = get_asset('/bad-import.js')
          asset.process(Time.now.to_f)

          assert(asset.error?)
        end

        it('returns false if there were no errors during processing') do
          asset = get_asset
          asset.process(Time.now.to_f)

          refute(asset.error?)
        end
      end

      ######################################################################################################
      ## Asset#inspect                                                                                    ##
      ######################################################################################################

      describe('#inspect') do
        it('returns a high-level object info string') do
          asset = get_asset('/bad-import.js')
          file = file_for(asset.path)

          asset.process(Time.now.to_f)

          assert_equal('#<Darkroom::Asset: '\
            '@errors=[#<Darkroom::AssetNotFoundError: Asset not found (referenced from /bad-import.js:1): '\
              '/does-not-exist.js>], '\
            '@extension=".js", '\
            "@file=\"#{file}\", "\
            '@fingerprint="afa0a5ffe7423f4b568f19a39b53b122", '\
            '@internal=false, '\
            '@minify=false, '\
            "@mtime=#{File.mtime(file).inspect}, "\
            '@path="/bad-import.js", '\
            '@path_versioned="/bad-import-afa0a5ffe7423f4b568f19a39b53b122.js"'\
          '>', asset.inspect)
        end
      end
    end
  end
end
