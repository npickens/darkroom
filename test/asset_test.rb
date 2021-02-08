class AssetTest < Minitest::Test
  describe('Darkroom') do
    describe('Asset') do
      before do
        @hello_file = File.expand_path(File.join('test', 'assets', 'hello.txt'))
        @hello_path = '/hello.txt'
      end

      describe('#internal?') do
        it('returns true if asset was initialized as internal') do
          asset = Darkroom::Asset.new(@hello_path, @hello_file, {}, internal: true)

          assert(asset.internal?)
        end

        it('returns false if asset was initialized as non-internal') do
          asset = Darkroom::Asset.new(@hello_path, @hello_file, {}, internal: false)

          refute(asset.internal?)
        end

        it('returns false if asset was initialized without specifying internal status') do
          asset = Darkroom::Asset.new(@hello_path, @hello_file, {})

          refute(asset.internal?)
        end
      end

      describe('#headers') do
        it('includes correct content type') do
          Darkroom::Asset::SPECS.each do |extension, spec|
            next if spec[:compile_lib]

            asset = Darkroom::Asset.new("hello#{extension}", '', {})
            assert_equal(spec[:content_type], asset.headers['Content-Type'])
          end
        end

        it('includes Cache-Control header if :versioned is not specified') do
          asset = Darkroom::Asset.new(@hello_path, @hello_file, {})
          headers = asset.headers

          assert_equal('public, max-age=31536000', headers['Cache-Control'])
          assert_nil(headers['ETag'])
        end

        it('includes Cache-Control header if :versioned is true') do
          asset = Darkroom::Asset.new(@hello_path, @hello_file, {})
          headers = asset.headers(versioned: true)

          assert_equal('public, max-age=31536000', headers['Cache-Control'])
          assert_nil(headers['ETag'])
        end

        it('includes ETag header if :versioned is false') do
          asset = Darkroom::Asset.new(@hello_path, @hello_file, {})
          asset.process(Time.now.to_f)

          headers = asset.headers(versioned: false)

          assert_equal('"09f7e02f1290be211da707a266f153b3"', headers['ETag'])
          assert_nil(headers['Cache-Control'])
        end
      end
    end
  end
end
