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
    end
  end
end
