class AssetTest < Minitest::Test
  describe('Darkroom') do
    describe('Asset') do
      ######################################################################################################
      ## Setup                                                                                            ##
      ######################################################################################################

      begin
        ASSET_DIR = File.expand_path(File.join('test', 'assets'))

        HELLO_PATH = '/hello.txt'
        HELLO_FILE = File.join(ASSET_DIR, HELLO_PATH)

        class AssetRequireLibsStub < Darkroom::Asset
          def require_libs() true end
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
