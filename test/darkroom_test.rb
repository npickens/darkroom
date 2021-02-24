require_relative('test_helper')

class DarkroomTest < Minitest::Test
  include(TestHelper)

  def self.context
    'Darkroom'
  end

  ##########################################################################################################
  ## Test #dump                                                                                           ##
  ##########################################################################################################

  test('#dump writes processed assets to a directory') do
    dump_dir = File.join(TEST_DIR, 'test_dump')
    darkroom = Darkroom.new(ASSET_DIR)

    darkroom.process
    darkroom.dump(dump_dir)

    %w[
      app-25f290825cb44d4cf57632abfa82c37e.js
      app-c21dbc03fb551f55b202b56908f8e4d5.css
      bad-import-afa0a5ffe7423f4b568f19a39b53b122.js
      bad-imports-afa0a5ffe7423f4b568f19a39b53b122.js
      good-import-f8b61e176e89f88e14213533a7f75742.js
      template-729d62af81cf5754f62c005fbe7da4b9.htx
    ].each do |file|
      assert(File.exists?(File.join(dump_dir, file)))
    end
  ensure
    FileUtils.rm_rf(dump_dir)
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
