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

        def get_asset(*args, **options)
          path = args[0] || JS_ASSET_PATH
          file = args[1] || File.join(ASSET_DIR, path)
          manifest = args[2] || {}

          Darkroom::Asset.new(path, file, manifest, **options)
        end
      end

      before do
        $:.unshift(DUMMY_LIBS_DIR)
      end

      after do
        $:.delete(DUMMY_LIBS_DIR)
        $".delete_if { |path| path.start_with?(DUMMY_LIBS_DIR) }

        Darkroom.send(:remove_const, :HTX) if defined?(Darkroom::HTX)
        Darkroom.send(:remove_const, :Uglifier) if defined?(Darkroom::Uglifier)

        refute(defined?(Darkroom::HTX), 'Expected HTX to be undefined.')
        refute(defined?(Darkroom::Uglifier), 'Expected Uglifier to be undefined.')
      end

      ######################################################################################################
      ## Asset#initialize                                                                                 ##
      ######################################################################################################

      describe('#initialize') do
        it('requires compile library if spec has one') do
          get_asset('/some-template.htx')

          assert(defined?(Darkroom::HTX), 'Expected HTX to be defined.')
        end

        it('requires minify library if spec has one and minification is enabled') do
          get_asset(minify: true)

          assert(defined?(Darkroom::Uglifier), 'Expected Uglifier to be defined.')
        end

        it('does not require minify library if spec has one and minification is not enabled') do
          get_asset

          refute(defined?(Darkroom::Uglifier), 'Expected Uglifier to be undefined.')
        end

        it('raises MissingLibraryError if compile library is not available') do
          $:.delete(DUMMY_LIBS_DIR)

          error = assert_raises(Darkroom::MissingLibraryError) do
            get_asset('/hello.htx')
          end

          assert_includes(error.inspect, Darkroom::Asset::SPECS['.htx'][:compile_lib])
        end

        it('raises MissingLibraryError if minify library is not available and minification is enabled') do
          $:.delete(DUMMY_LIBS_DIR)

          error = assert_raises(Darkroom::MissingLibraryError) do
            get_asset(minify: true)
          end

          assert_includes(error.inspect, Darkroom::Asset::SPECS['.js'][:minify_lib])
        end
      end

      ######################################################################################################
      ## Asset#content_type                                                                               ##
      ######################################################################################################

      describe('#content_type') do
        it('returns the correct HTTP MIME string for the asset') do
          Darkroom::Asset::SPECS.each do |extension, spec|
            asset = get_asset("hello#{extension}")
            assert_equal(spec[:content_type], Darkroom::Asset::SPECS[extension][:content_type])
          end
        end
      end

      ######################################################################################################
      ## Asset#headers                                                                                    ##
      ######################################################################################################

      describe('#headers') do
        it('includes correct content type') do
          Darkroom::Asset::SPECS.each do |extension, spec|
            asset = get_asset("hello#{extension}")
            assert_equal(spec[:content_type], asset.headers['Content-Type'])
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
          file = File.join(ASSET_DIR, '/bad-import.js')
          asset = get_asset('/bad-import.js', file)
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
