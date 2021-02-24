require('fileutils')
require_relative('test_helper')

class DarkroomTest < Minitest::Test
  include(TestHelper)

  DUMP_DIR = File.join(TEST_DIR, 'dump').freeze
  DUMP_DIR_EXISTING_FILE = File.join(DUMP_DIR, 'existing.txt').freeze

  def self.context
    'Darkroom'
  end

  ##########################################################################################################
  ## Hooks                                                                                                ##
  ##########################################################################################################

  def setup
    @@darkroom = (@@default_darkroom ||= darkroom)
  end

  ##########################################################################################################
  ## Test #asset_path                                                                                     ##
  ##########################################################################################################

  test('#asset_path returns nil if the asset does not exist') do
    assert_nil(darkroom.asset_path('/does-not-exist.js'))
  end

  test('#asset_path returns versioned path by default if asset is not pristine') do
    assert_equal(JS_ASSET_PATH_VERSIONED, darkroom.asset_path(JS_ASSET_PATH))
  end

  test('#asset_path returns unversioned path by default if asset is pristine') do
    assert_equal(PRISTINE_ASSET_PATH, darkroom.asset_path(PRISTINE_ASSET_PATH))
  end

  test('#asset_path returns versioned asset path if `versioned` option is true') do
    assert_equal(JS_ASSET_PATH_VERSIONED, darkroom.asset_path(JS_ASSET_PATH, versioned: true))
    assert_equal(PRISTINE_ASSET_PATH_VERSIONED, darkroom.asset_path(PRISTINE_ASSET_PATH, versioned: true))
  end

  test('#asset_path returns unversioned asset path if `versioned` option is false') do
    assert_equal(JS_ASSET_PATH, darkroom.asset_path(JS_ASSET_PATH, versioned: false))
    assert_equal(PRISTINE_ASSET_PATH, darkroom.asset_path(PRISTINE_ASSET_PATH, versioned: false))
  end

  test('#asset_path includes a round-robin selected host if any hosts are configured') do
    host = 'https://cdn1.darkroom'
    hosts = %w[https://cdn1.darkroom https://cdn2.darkroom https://cdn3.darkroom]

    configure_darkroom(host: host)
    assert_equal("#{host}#{JS_ASSET_PATH_VERSIONED}", darkroom.asset_path(JS_ASSET_PATH))
    assert_equal("#{host}#{JS_ASSET_PATH_VERSIONED}", darkroom.asset_path(JS_ASSET_PATH))

    configure_darkroom(hosts: hosts)
    assert_equal("#{hosts[0]}#{JS_ASSET_PATH_VERSIONED}", darkroom.asset_path(JS_ASSET_PATH))
    assert_equal("#{hosts[1]}#{JS_ASSET_PATH_VERSIONED}", darkroom.asset_path(JS_ASSET_PATH))
    assert_equal("#{hosts[2]}#{CSS_ASSET_PATH_VERSIONED}", darkroom.asset_path(CSS_ASSET_PATH))
    assert_equal("#{hosts[0]}#{JS_ASSET_PATH_VERSIONED}", darkroom.asset_path(JS_ASSET_PATH))
  end

  test('#asset_path includes prefix if one is configured and asset is not pristine') do
    configure_darkroom(prefix: '/static')

    assert_match(/^\/static/, darkroom.asset_path(JS_ASSET_PATH))
  end

  test('#asset_path does not include prefix if one is configured and asset is pristine') do
    configure_darkroom(prefix: '/static')

    refute_match(/^\/static/, darkroom.asset_path(PRISTINE_ASSET_PATH))
  end

  ##########################################################################################################
  ## Test #asset_path!                                                                                    ##
  ##########################################################################################################

  test('#asset_path! raises AssetNotFoundError if asset does not exist') do
    path = '/does-not-exist.js'

    error = assert_raises(Darkroom::AssetNotFoundError) do
      darkroom.asset_path!(path)
    end

    assert_includes(error.inspect, path)
  end

  ##########################################################################################################
  ## Test #dump                                                                                           ##
  ##########################################################################################################

  def setup_dump_dir(with_file: false)
    FileUtils.rm_rf(DUMP_DIR)
    FileUtils.mkdir_p(DUMP_DIR)

    File.write(DUMP_DIR_EXISTING_FILE, 'Existing file...') if with_file
  end

  test('#dump creates target directory if it does not exist') do
    FileUtils.rm_rf(DUMP_DIR)
    darkroom.dump(DUMP_DIR) rescue nil

    assert(File.directory?(DUMP_DIR))
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump writes processed assets to a directory') do
    setup_dump_dir
    darkroom.dump(DUMP_DIR)

    Dir.glob(File.join(DUMP_DIR, '*')).each do |file|
      assert_equal(darkroom.asset("/#{File.basename(file)}").content, File.read(file))
    end
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump does not include internal assets') do
    setup_dump_dir
    configure_darkroom(internal_pattern: /\.js$/)
    darkroom.dump(DUMP_DIR)

    refute(Dir.glob(File.join(DUMP_DIR, '*')).empty?)
    assert(Dir.glob(File.join(DUMP_DIR, '*.js')).empty?)
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump does not delete anything in target directory by default') do
    setup_dump_dir(with_file: true)
    darkroom.dump(DUMP_DIR)

    assert(File.exists?(DUMP_DIR_EXISTING_FILE))
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump deletes everything in target directory if `clear` option is true') do
    setup_dump_dir(with_file: true)
    darkroom.dump(DUMP_DIR, clear: true)

    refute(File.exists?(DUMP_DIR_EXISTING_FILE))
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump does not delete anything in target directory if `clear` option is false') do
    setup_dump_dir(with_file: true)
    darkroom.dump(DUMP_DIR, clear: false)

    assert(File.exists?(DUMP_DIR_EXISTING_FILE))
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump includes pristine assets by default') do
    setup_dump_dir
    darkroom.dump(DUMP_DIR)

    assert(File.exists?(File.join(DUMP_DIR, PRISTINE_ASSET_PATH)))
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump includes pristine assets if `include_pristine` option is true') do
    setup_dump_dir
    darkroom.dump(DUMP_DIR, include_pristine: true)

    assert(File.exists?(File.join(DUMP_DIR, PRISTINE_ASSET_PATH)))
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump does not include pristine assets if `include_pristine` option is false') do
    setup_dump_dir
    darkroom.dump(DUMP_DIR, include_pristine: false)

    refute(File.exists?(File.join(DUMP_DIR, PRISTINE_ASSET_PATH)))
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  ##########################################################################################################
  ## Test #inspect                                                                                        ##
  ##########################################################################################################

  test('#inspect returns a high-level object info string') do
    configure_darkroom(
      hosts: 'https://cdn1.hello.world',
      prefix: '/static',
      pristine: '/hi.txt',
      minified_pattern: /\.minified\.*/,
      internal_pattern: /^\/private\//,
      min_process_interval: 1,
    )

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

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def darkroom
    defined?(@@darkroom) ? @@darkroom : configure_darkroom
  end

  def configure_darkroom(**options)
    @@darkroom = Darkroom.new(ASSET_DIR, **options)
    @@darkroom.process

    @@darkroom
  end
end
