require('fileutils')
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
    darkroom = Darkroom.new(ASSET_DIR)
    darkroom.process
    darkroom.dump(DUMP_DIR)

    Dir.glob(File.join(DUMP_DIR, '*')).each do |file|
      assert_equal(darkroom.asset("/#{File.basename(file)}").content, File.read(file))
    end
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump does not include internal files') do
    internal_pattern = /\.js$/

    darkroom = Darkroom.new(ASSET_DIR, internal_pattern: internal_pattern)
    darkroom.process
    darkroom.dump(DUMP_DIR)

    Dir.glob(File.join(DUMP_DIR, '*')).each do |file|
      refute_match(internal_pattern, file)
    end
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump clears directory if clear option is true') do
    darkroom = Darkroom.new(ASSET_DIR)
    darkroom.process

    some_file = File.join(DUMP_DIR, 'hello.txt')

    FileUtils.mkdir_p(DUMP_DIR)
    File.write(some_file, 'Hello World!')

    darkroom.dump(DUMP_DIR)
    assert(File.exists?(some_file), 'Expected file to exist')

    darkroom.dump(DUMP_DIR, clear: false)
    assert(File.exists?(some_file), 'Expected file to exist')

    darkroom.dump(DUMP_DIR, clear: true)
    refute(File.exists?(some_file), 'Expected file to have been deleted')
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump does not include pristine assets if include_pristine option is false') do
    darkroom = Darkroom.new(ASSET_DIR, pristine: JS_ASSET_PATH)
    darkroom.process

    file = File.join(DUMP_DIR, JS_ASSET_PATH)

    darkroom.dump(DUMP_DIR, clear: true)
    assert(File.exists?(file), "Expected #{JS_ASSET_PATH} to exist")

    darkroom.dump(DUMP_DIR, clear: true, include_pristine: true)
    assert(File.exists?(file), "Expected #{JS_ASSET_PATH} to exist")

    darkroom.dump(DUMP_DIR, clear: true, include_pristine: false)
    refute(File.exists?(file), "Expected #{JS_ASSET_PATH} to not exist")
  ensure
    FileUtils.rm_rf(DUMP_DIR)
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
