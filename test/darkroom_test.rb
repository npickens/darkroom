# frozen_string_literal: true

require('fileutils')
require_relative('test_helper')

class DarkroomTest < Minitest::Test
  include(TestHelper)

  TMP_ASSET_PATH = '/tmp.txt'
  TMP_ASSET_FILE = File.join(ASSET_DIR, TMP_ASSET_PATH).freeze

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
  ## Test #process                                                                                        ##
  ##########################################################################################################

  test('#process skips processing if minimum process interval has not elapsed since last call') do
    configure_darkroom(min_process_interval: 2)

    File.write(TMP_ASSET_FILE, 'Temporary...')
    darkroom.process

    assert_nil(darkroom.asset(TMP_ASSET_PATH))
  ensure
    FileUtils.rm_rf(TMP_ASSET_FILE)
  end

  test('#process skips processing if another thread is currently processing') do
    mutex_mock = Minitest::Mock.new
    def mutex_mock.locked?() true end
    def mutex_mock.synchronize(&block) block.call end

    Mutex.stub(:new, mutex_mock) do
      configure_darkroom(min_process_interval: 0)

      File.write(TMP_ASSET_FILE, 'Temporary...')
      darkroom.process
    end

    assert_nil(darkroom.asset(TMP_ASSET_PATH))
  ensure
    FileUtils.rm_rf(TMP_ASSET_FILE)
  end

  test('#process includes DuplicateAssetError if an asset with the same path is in multiple load paths') do
    FileUtils.touch(File.join(BAD_ASSET_DIR, JS_ASSET_PATH))

    configure_darkroom(ASSET_DIR, BAD_ASSET_DIR)
    darkroom.process

    assert_kind_of(Darkroom::DuplicateAssetError, darkroom.errors.first)
    assert_includes(darkroom.errors.first.inspect, JS_ASSET_PATH)
  ensure
    FileUtils.rm_rf(File.join(BAD_ASSET_DIR, JS_ASSET_PATH))
  end

  ##########################################################################################################
  ## Test #process!                                                                                       ##
  ##########################################################################################################

  test('#process! raises ProcessingError if there were one or more errors during processing') do
    configure_darkroom(ASSET_DIR, BAD_ASSET_DIR)

    error = assert_raises(Darkroom::ProcessingError) do
      darkroom.process!
    end

    assert_includes(error.inspect, '/does-not-exist.js')
    assert_includes(error.inspect, '/also-does-not-exist.js')
  end

  ##########################################################################################################
  ## Test #error?                                                                                         ##
  ##########################################################################################################

  test('#error? returns false if there were no errors during processing') do
    refute(darkroom.error?)
  end

  test('#error? returns true if there were one or more errors during processing') do
    configure_darkroom(ASSET_DIR, BAD_ASSET_DIR)

    assert(darkroom.error?)
  end

  ##########################################################################################################
  ## Test #asset                                                                                          ##
  ##########################################################################################################

  test('#asset returns nil if asset does not exist') do
    assert_nil(darkroom.asset('/does-not-exist.js'))
  end

  test('#asset returns asset for unversioned path') do
    assert_equal(File.read(JS_ASSET_FILE), darkroom.asset(JS_ASSET_PATH)&.content)
  end

  test('#asset returns asset for versioned path') do
    assert_equal(File.read(JS_ASSET_FILE), darkroom.asset(JS_ASSET_PATH_VERSIONED)&.content)
  end

  test('#asset only returns asset if path includes prefix when a prefix is configured and asset is not '\
      'pristine') do
    configure_darkroom(prefix: '/static')

    assert(darkroom.asset("/static#{JS_ASSET_PATH}"))
    assert(darkroom.asset("/static#{JS_ASSET_PATH_VERSIONED}"))

    assert_nil(darkroom.asset(JS_ASSET_PATH))
    assert_nil(darkroom.asset(JS_ASSET_PATH_VERSIONED))
  end

  test('#asset only returns asset if path excludes prefix when a prefix is configured and asset is '\
      'pristine') do
    configure_darkroom(prefix: '/static')

    assert(darkroom.asset(PRISTINE_ASSET_PATH))
    assert(darkroom.asset(PRISTINE_ASSET_PATH_VERSIONED))

    assert_nil(darkroom.asset("/static#{PRISTINE_ASSET_PATH}"))
    assert_nil(darkroom.asset("/static#{PRISTINE_ASSET_PATH_VERSIONED}"))
  end

  test('#asset returns nil if asset is internal') do
    configure_darkroom(internal_pattern: /\.js$/)

    assert_nil(darkroom.asset(JS_ASSET_PATH))
  end

  ##########################################################################################################
  ## Test #asset_path                                                                                     ##
  ##########################################################################################################

  test('#asset_path raises AssetNotFoundError if asset does not exist') do
    path = '/does-not-exist.js'

    error = assert_raises(Darkroom::AssetNotFoundError) do
      darkroom.asset_path(path)
    end

    assert_includes(error.inspect, path)
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
    configure_darkroom(ASSET_DIR, BAD_ASSET_DIR,
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
      "@globs={\"#{ASSET_DIR}\"=>\"#{ASSET_DIR}/**/*{#{Darkroom::Asset.extensions.join(',')}}\", "\
        "\"#{BAD_ASSET_DIR}\"=>\"#{BAD_ASSET_DIR}/**/*{#{Darkroom::Asset.extensions.join(',')}}\"}, "\
      '@hosts=["https://cdn1.hello.world"], '\
      '@internal_pattern=/^\\/private\\//, '\
      "@last_processed_at=#{darkroom.instance_variable_get(:@last_processed_at)}, "\
      '@min_process_interval=1, '\
      '@minified_pattern=/\\.minified\\.*/, '\
      '@minify=false, '\
      '@prefix="/static", '\
      '@pristine=#<Set: {"/favicon.ico", "/mask-icon.svg", "/humans.txt", "/robots.txt", "/hi.txt"}>'\
    '>'.split(INSPECT_SPLIT).join(INSPECT_JOIN), darkroom.inspect.split(INSPECT_SPLIT).join(INSPECT_JOIN))
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def darkroom
    defined?(@@darkroom) ? @@darkroom : configure_darkroom
  end

  def configure_darkroom(*args, **options)
    @@darkroom = Darkroom.new(*(args.empty? ? [ASSET_DIR] : args), **options)
    @@darkroom.process

    @@darkroom
  end
end
