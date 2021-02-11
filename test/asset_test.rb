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

        HELLO_PATH = '/hello.txt'
        HELLO_FILE = File.join(ASSET_DIR, HELLO_PATH)

        specs = Darkroom::Asset::SPECS.dup.merge!(
          '.dummy' => {
            content_type: 'text/dummy',
            compile_lib: File.join(DUMMY_LIBS_DIR, 'compile.rb').freeze,
            minify_lib: File.join(DUMMY_LIBS_DIR, 'minify.rb').freeze,
          }.freeze,

          '.bad-compile' => {
            content_type: 'text/bad-compile',
            compile_lib: File.join(DUMMY_LIBS_DIR, 'bad-compile.rb').freeze,
            minify_lib: File.join(DUMMY_LIBS_DIR, 'minify.rb').freeze,
          }.freeze,

          '.bad-minify' => {
            content_type: 'text/bad-minify',
            compile_lib: File.join(DUMMY_LIBS_DIR, 'compile.rb').freeze,
            minify_lib: File.join(DUMMY_LIBS_DIR, 'bad-minify.rb').freeze,
          }.freeze,
        ).freeze

        Darkroom::Asset.send(:remove_const, :SPECS)
        Darkroom::Asset.const_set(:SPECS, specs)

        class AssetRequireLibsStub < Darkroom::Asset
          def require_libs() true end
        end
      end

      ######################################################################################################
      ## Asset#initialize                                                                                 ##
      ######################################################################################################

      describe('#initialize') do
        before do
          if defined?(Darkroom::DummyCompile)
            $".delete(Darkroom::Asset::SPECS['.dummy'][:compile_lib])
            Darkroom.send(:remove_const, :DummyCompile)
          end

          if defined?(Darkroom::DummyMinify)
            $".delete(Darkroom::Asset::SPECS['.dummy'][:minify_lib])
            Darkroom.send(:remove_const, :DummyMinify)
          end
        end

        it('requires compile library if spec has one') do
          Darkroom::Asset.new('/hello.dummy', '', {})

          assert(!!defined?(Darkroom::DummyCompile), 'Expected Darkroom::DummyCompile to be defined.')
        end

        it('requires minify library if spec has one and minification is enabled') do
          Darkroom::Asset.new('/hello.dummy', '', {}, minify: true)
          assert(!!defined?(Darkroom::DummyMinify), 'Expected Darkroom::DummyMinify to be defined.')
        end

        it('does not require minify library if spec has one and minification is not enabled') do
          Darkroom::Asset.new('/hello.dummy', '', {})
          refute(!!defined?(Darkroom::DummyMinify), 'Expected Darkroom::DummyMinify to be undefined.')
        end

        it('raises MissingLibraryError if compile library is not available') do
          assert_raises(Darkroom::MissingLibraryError) do
            Darkroom::Asset.new('/hello.bad-compile', '', {})
          end
        end

        it('raises MissingLibraryError if minify library is not available and minification is enabled') do
          assert_raises(Darkroom::MissingLibraryError) do
            Darkroom::Asset.new('/hello.bad-minify', '', {}, minify: true)
          end
        end
      end

      ######################################################################################################
      ## Asset#content_type                                                                               ##
      ######################################################################################################

      describe('#content_type') do
        it('returns the correct HTTP MIME string for the asset') do
          Darkroom::Asset::SPECS.each do |extension, spec|
            asset = AssetRequireLibsStub.new("hello#{extension}", '', {})
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
            asset = AssetRequireLibsStub.new("hello#{extension}", '', {})
            assert_equal(spec[:content_type], asset.headers['Content-Type'])
          end
        end

        it('includes Cache-Control header if :versioned is not specified') do
          asset = AssetRequireLibsStub.new(HELLO_PATH, HELLO_FILE, {})
          headers = asset.headers

          assert_equal('public, max-age=31536000', headers['Cache-Control'])
          assert_nil(headers['ETag'])
        end

        it('includes Cache-Control header if :versioned is true') do
          asset = AssetRequireLibsStub.new(HELLO_PATH, HELLO_FILE, {})
          asset.process(Time.now.to_f)

          headers = asset.headers(versioned: true)

          assert_equal('public, max-age=31536000', headers['Cache-Control'])
          assert_nil(headers['ETag'])
        end

        it('includes ETag header if :versioned is false') do
          asset = AssetRequireLibsStub.new(HELLO_PATH, HELLO_FILE, {})
          asset.process(Time.now.to_f)

          headers = asset.headers(versioned: false)

          assert_equal('"09f7e02f1290be211da707a266f153b3"', headers['ETag'])
          assert_nil(headers['Cache-Control'])
        end
      end

      ######################################################################################################
      ## Asset#internal?                                                                                  ##
      ######################################################################################################

      describe('#internal?') do
        it('returns true if asset was initialized as internal') do
          asset = AssetRequireLibsStub.new(HELLO_PATH, HELLO_FILE, {}, internal: true)

          assert(asset.internal?)
        end

        it('returns false if asset was initialized as non-internal') do
          asset = AssetRequireLibsStub.new(HELLO_PATH, HELLO_FILE, {}, internal: false)

          refute(asset.internal?)
        end

        it('returns false if asset was initialized without specifying internal status') do
          asset = AssetRequireLibsStub.new(HELLO_PATH, HELLO_FILE, {})

          refute(asset.internal?)
        end
      end

      ######################################################################################################
      ## Asset#error?                                                                                     ##
      ######################################################################################################

      describe('#error?') do
        it('returns true if there were one or more errors during processing') do
          path = '/bad-import.js'
          asset = AssetRequireLibsStub.new(path, File.join(ASSET_DIR, path), {})

          asset.process(Time.now.to_f)

          assert(asset.error?)
        end

        it('returns false if there were no errors during processing') do
          asset = AssetRequireLibsStub.new(HELLO_PATH, HELLO_FILE, {})

          asset.process(Time.now.to_f)

          refute(asset.error?)
        end
      end
    end
  end
end
