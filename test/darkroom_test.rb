# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('test_helper')

class DarkroomTest < Minitest::Test
  include(TestHelper)

  DUMP_DIR = File.join(TMP_DIR, 'dump').freeze
  DUMP_DIR_EXISTING_FILE = File.join(DUMP_DIR, 'existing.txt').freeze

  class Ext < Darkroom::Delegate
    content_type('text/ext')
  end

  ##########################################################################################################
  ## .register                                                                                            ##
  ##########################################################################################################

  test('.register accepts one extension and a content type') do
    delegate = Darkroom.register('.ext', 'text/ext')

    assert_operator(delegate, :<, Darkroom::Delegate)
    assert_equal(delegate, Darkroom.delegate('.ext'))
    assert_equal('text/ext', delegate.content_type)
  end

  test('.register accepts multiple extensions and a content type') do
    delegate = Darkroom.register('.ext1', '.ext2', 'text/ext')

    assert_operator(delegate, :<, Darkroom::Delegate)
    assert_equal(delegate, Darkroom.delegate('.ext1'))
    assert_equal(delegate, Darkroom.delegate('.ext2'))
    assert_equal('text/ext', delegate.content_type)
  end

  test('.register accepts one extension and a block') do
    delegate = Darkroom.register('.ext') do
      content_type('text/ext')
    end

    assert_operator(delegate, :<, Darkroom::Delegate)
    assert_equal(delegate, Darkroom.delegate('.ext'))
    assert_equal('text/ext', delegate.content_type)
  end

  test('.register accepts multiple extensions and a block') do
    delegate = Darkroom.register('.ext1', '.ext2') do
      content_type('text/ext')
    end

    assert_operator(delegate, :<, Darkroom::Delegate)
    assert_equal(delegate, Darkroom.delegate('.ext1'))
    assert_equal(delegate, Darkroom.delegate('.ext2'))
    assert_equal('text/ext', delegate.content_type)
  end

  test('.register accepts one extension, a content type, and a block') do
    delegate = Darkroom.register('.ext', 'text/ext') do
      content_type('text/extra')
    end

    assert_operator(delegate, :<, Darkroom::Delegate)
    assert_equal(delegate, Darkroom.delegate('.ext'))
    assert_equal('text/extra', delegate.content_type)
  end

  test('.register accepts multiple extensions, a content type, and a block') do
    delegate = Darkroom.register('.ext1', '.ext2', 'text/ext') do
      content_type('text/extra')
    end

    assert_operator(delegate, :<, Darkroom::Delegate)
    assert_equal(delegate, Darkroom.delegate('.ext1'))
    assert_equal(delegate, Darkroom.delegate('.ext2'))
    assert_equal('text/extra', delegate.content_type)
  end

  test('.register accepts one extension and a Delegate subclass') do
    delegate = Darkroom.register('.ext', Ext)

    assert_equal(Ext, delegate)
    assert_equal(delegate, Darkroom.delegate('.ext'))
    assert_equal('text/ext', delegate.content_type)
  end

  test('.register accepts multiple extensions and a Delegate subclass') do
    delegate = Darkroom.register('.ext1', '.ext2', Ext)

    assert_equal(Ext, delegate)
    assert_equal(delegate, Darkroom.delegate('.ext1'))
    assert_equal(delegate, Darkroom.delegate('.ext2'))
    assert_equal('text/ext', delegate.content_type)
  end

  test('.register accepts one extension, a Delegate subclass, and a block') do
    delegate = Darkroom.register('.ext', Ext) do
      content_type('text/extra')
    end

    assert_operator(delegate, :<, Ext)
    assert_equal(delegate, Darkroom.delegate('.ext'))
    assert_equal('text/extra', delegate.content_type)
  end

  test('.register accepts multiple extensions, a Delegate subclass, and a block') do
    delegate = Darkroom.register('.ext1', '.ext2', Ext) do
      content_type('text/extra')
    end

    assert_operator(delegate, :<, Ext)
    assert_equal(delegate, Darkroom.delegate('.ext1'))
    assert_equal(delegate, Darkroom.delegate('.ext2'))
    assert_equal('text/extra', delegate.content_type)
  end

  ##########################################################################################################
  ## #process                                                                                             ##
  ##########################################################################################################

  test('#process returns true if processing was performed') do
    write_files('/assets/app.js' => "console.log('Hello')")

    darkroom('/assets')
    did_process = darkroom.process

    refute_error(darkroom.errors)
    assert(did_process)
  end

  test('#process skips processing and returns false if last run was less than min_process_interval ago') do
    write_files('/assets/app.js' => "console.log('Hello')")

    darkroom('/assets', min_process_interval: 9999)
    darkroom.process

    refute_error(darkroom.errors)

    write_files('/assets/tmp.txt' => 'Temporary...')
    did_process = darkroom.process

    refute_error(darkroom.errors)

    refute(did_process)
    assert(darkroom.asset('/app.js'))
    assert_nil(darkroom.asset('/tmp.txt'))
  end

  test('#process skips processing and returns false if another thread is currently processing') do
    mutex_mock = Minitest::Mock.new

    def mutex_mock.locked?
      (@locked_calls = (@locked_calls || 0) + 1) == 2
    end

    def mutex_mock.synchronize(&block)
      block.call
    end

    Mutex.stub(:new, mutex_mock) do
      write_files('/assets/app.js' => "console.log('Hello')")

      darkroom('/assets', min_process_interval: 0)
      did_process = darkroom.process

      refute_error(darkroom.errors)
      assert(did_process)

      write_files('/assets/tmp.txt' => 'Temporary...')
      did_process = darkroom.process

      refute_error(darkroom.errors)
      refute(did_process)
    end

    assert(darkroom.asset('/app.js'))
    assert_nil(darkroom.asset('/tmp.txt'))
  end

  test('#process registers InvalidPathError if an asset path contains one or more disallowed character') do
    paths = [
      "/single'quote.js",
      '/double"quote.js',
      '/back`tick.js',
      '/equal=sign.js',
      '/less<than.js',
      '/greater>than.js',
      '/question?mark.js',
      '/spa ce.js',
    ].sort

    write_files(paths.map { |path| ["/assets#{path}", '[...]'] }.to_h)

    darkroom('/assets')
    darkroom.process

    assert_error(
      paths.map do |path|
        '#<Darkroom::InvalidPathError: Asset path contains one or more invalid characters ' \
          "('\"`=<>? ): #{path}>"
      end,
      darkroom.errors
    )
  end

  test('#process registers DuplicateAssetError if an asset with the same path is in multiple load paths') do
    write_files(
      '/assets/app.js' => "console.log('Hello')",
      '/other-assets/app.js' => "console.log('Hello again')",
    )

    darkroom('/assets', '/other-assets')
    darkroom.process

    assert_error("#<Darkroom::DuplicateAssetError: Asset file exists in both #{full_path('/assets')} " \
      "and #{full_path('/other-assets')}: /app.js>", darkroom.errors)
  end

  test('#process minifies asset if and only if it matches :entry and does not match :minified') do
    write_files(
      '/assets/app.js' => "console.log('Hello')",
      '/assets/app.css' => 'body { background: white; }',
      '/assets/other.js' => "console.log('World')",
      '/assets/other.css' => 'div { border: 1px solid black; }',
    )

    darkroom(
      '/assets',
      entries: ['/app.css', /app\.js/],
      minify: true,
      minified: ['/app.txt', /\.css/],
    )

    require('terser')

    Terser.stub(:compile, '[minified]') do
      darkroom.process
    end

    refute_error(darkroom.errors)

    assert_equal('[minified]',                       darkroom.manifest('/app.js').content)
    assert_equal('body { background: white; }',      darkroom.manifest('/app.css').content)
    assert_equal("console.log('World')",             darkroom.manifest('/other.js').content)
    assert_equal('div { border: 1px solid black; }', darkroom.manifest('/other.css').content)
  end

  ##########################################################################################################
  ## #process!                                                                                            ##
  ##########################################################################################################

  test('#process! calls #process and returns its return value') do
    assert_equal('some value', darkroom.stub(:process, 'some value') { darkroom.process! })
  end

  test('#process! raises ProcessingError if there were one or more errors during processing') do
    write_files(
      '/assets/bad-imports.js' => <<~JS,
        import '/does-not-exist.js'
        import '/also-does-not-exist.js'

        console.log('Hello')
      JS
    )

    darkroom('/assets')

    error = assert_raises(Darkroom::ProcessingError) do
      darkroom.process!
    end

    assert_equal(
      <<~TEXT.strip,
        Errors were encountered while processing assets:
          /bad-imports.js:1: Asset not found: /does-not-exist.js
          /bad-imports.js:2: Asset not found: /also-does-not-exist.js
      TEXT
      error.to_s
    )
  end

  test('#process! does not raise ProcessingError if last run was less than min_process_interval ago') do
    write_files('/assets/app.js' => 'console.log("Hello")')

    darkroom('/assets', min_process_interval: 9999)
    darkroom.process!

    write_files('/assets/app.js' => 'import "/does-not-exist.js"')

    begin
      darkroom.process!
    rescue Darkroom::ProcessingError
      flunk('Darkroom::ProcessingError not expected but was raised')
    end
  end

  ##########################################################################################################
  ## #error?                                                                                              ##
  ##########################################################################################################

  test('#error? returns false if there were no errors during processing') do
    write_files('/assets/app.js' => "console.log('Hello')")

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)
    refute(darkroom.error?)
  end

  test('#error? returns true if there were one or more errors during processing') do
    write_files(
      '/assets/bad-import.js' => <<~JS,
        import '/does-not-exist.js'

        console.log('Hello')
      JS
    )

    darkroom('/assets')
    darkroom.process

    assert_error('#<Darkroom::AssetNotFoundError: /bad-import.js:1: Asset not found: ' \
      '/does-not-exist.js>', darkroom.errors)
    assert(darkroom.error?)
  end

  ##########################################################################################################
  ## #asset                                                                                               ##
  ##########################################################################################################

  test('#asset returns nil if asset does not exist') do
    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)
    assert_nil(darkroom.asset('/does-not-exist.js'))
  end

  test('#asset returns asset for unversioned path') do
    content = "console.log('Hello')"
    write_files('/assets/app.js' => content)

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)

    asset = darkroom.asset('/app.js')

    assert(asset)
    assert_equal(content, asset.content)
  end

  test('#asset returns asset for versioned path') do
    content = "console.log('Hello')"
    write_files('/assets/app.js' => content)

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)

    asset = darkroom.asset('/app-ef0f76b822009ab847bd6a370e911556.js')

    assert(asset)
    assert_equal(content, asset.content)
  end

  test('#asset only returns asset if path includes prefix when a prefix is configured and asset is not ' \
      'pristine') do
    write_files('/assets/app.js' => "console.log('Hello')")

    darkroom('/assets', prefix: '/static')
    darkroom.process

    refute_error(darkroom.errors)

    assert(darkroom.asset('/static/app.js'))
    assert(darkroom.asset('/static/app-ef0f76b822009ab847bd6a370e911556.js'))

    assert_nil(darkroom.asset('/app.js'))
    assert_nil(darkroom.asset('/app-aec92e09ce672c46c094c95b1208cd09.js'))
  end

  test('#asset only returns asset if path excludes prefix when a prefix is configured and asset is ' \
      'pristine') do
    write_files('/assets/pristine.txt' => 'Hello')

    darkroom('/assets', prefix: '/static', pristine: '/pristine.txt')
    darkroom.process

    refute_error(darkroom.errors)

    assert_nil(darkroom.asset('/static/pristine.txt'))
    assert_nil(darkroom.asset('/static/pristine-8b1a9953c4611296a827abf8c47804d7.txt'))

    assert(darkroom.asset('/pristine.txt'))
    assert(darkroom.asset('/pristine-8b1a9953c4611296a827abf8c47804d7.txt'))
  end

  test('#asset returns nil if asset is not an entry point') do
    write_files('/assets/components/header.css' => 'header { background: white; }')

    darkroom('/assets', entries: %r{^/[^/]+$})
    darkroom.process

    refute_error(darkroom.errors)
    assert_nil(darkroom.asset('/components/header.htx'))
  end

  test('#asset returns asset if path is not explicitly an entry point but is pristine') do
    write_files('/assets/pristine.txt' => 'Hello')

    darkroom('/assets', entries: %r{^/controllers/.+}, pristine: '/pristine.txt')
    darkroom.process

    refute_error(darkroom.errors)
    assert(darkroom.asset('/pristine.txt'))
  end

  ##########################################################################################################
  ## #asset_path                                                                                          ##
  ##########################################################################################################

  test('#asset_path raises AssetNotFoundError if asset does not exist') do
    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)

    error = assert_raises(Darkroom::AssetNotFoundError) do
      darkroom.asset_path('/does-not-exist.js')
    end

    assert_equal('Asset not found: /does-not-exist.js', error.to_s)
  end

  test('#asset_path returns versioned path by default if asset is not pristine') do
    write_files('/assets/app.js' => "console.log('Hello')")

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)
    assert_equal('/app-ef0f76b822009ab847bd6a370e911556.js', darkroom.asset_path('/app.js'))
  end

  test('#asset_path returns unversioned path by default if asset is pristine') do
    write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)
    assert_equal('/robots.txt', darkroom.asset_path('/robots.txt'))
  end

  test('#asset_path returns versioned asset path if `versioned` option is true') do
    write_files(
      '/assets/app.js' => "console.log('Hello')",
      '/assets/robots.txt' => "User-agent: *\nDisallow:",
    )

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)

    assert_equal(
      '/app-ef0f76b822009ab847bd6a370e911556.js',
      darkroom.asset_path('/app.js', versioned: true)
    )

    assert_equal(
      '/robots-50d8a018e8ae96732c8a2ba663c61d4e.txt',
      darkroom.asset_path('/robots.txt', versioned: true)
    )
  end

  test('#asset_path returns unversioned asset path if `versioned` option is false') do
    write_files(
      '/assets/app.js' => "console.log('Hello')",
      '/assets/robots.txt' => "User-agent: *\nDisallow:",
    )

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)

    assert_equal('/app.js', darkroom.asset_path('/app.js', versioned: false))
    assert_equal('/robots.txt', darkroom.asset_path('/robots.txt', versioned: false))
  end

  test('#asset_path includes a round-robin selected host if any hosts are configured') do
    write_files(
      '/assets/app.js' => "console.log('Hello')",
      '/assets/app.css' => 'body { background: white; }',
    )

    host = 'https://cdn1.darkroom'
    hosts = %w[https://cdn1.darkroom https://cdn2.darkroom https://cdn3.darkroom]

    darkroom('/assets', host: host)
    darkroom.process

    refute_error(darkroom.errors)

    assert_equal("#{host}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))
    assert_equal("#{host}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))

    darkroom('/assets', hosts: hosts)
    darkroom.process

    refute_error(darkroom.errors)

    assert_equal("#{hosts[0]}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))
    assert_equal("#{hosts[1]}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))
    assert_equal("#{hosts[2]}/app-c7319c7b3b95111f028f6f4161ebd371.css", darkroom.asset_path('/app.css'))
    assert_equal("#{hosts[0]}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))
  end

  test('#asset_path includes prefix if one is configured and asset is not pristine') do
    write_files('/assets/app.js' => "console.log('Hello')")

    darkroom('/assets', prefix: '/static')
    darkroom.process

    refute_error(darkroom.errors)
    assert_equal('/static/app-ef0f76b822009ab847bd6a370e911556.js', darkroom.asset_path('/app.js'))
  end

  test('#asset_path does not include prefix if one is configured and asset is pristine') do
    write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

    darkroom('/assets', prefix: '/static')
    darkroom.process

    refute_error(darkroom.errors)
    assert_equal('/robots.txt', darkroom.asset_path('/robots.txt'))
  end

  ##########################################################################################################
  ## #asset_integrity                                                                                     ##
  ##########################################################################################################

  test('#asset_integrity returns subresource integrity string according to algorithm argument') do
    write_files('/assets/app.js' => "console.log('Hello')")

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)

    assert_equal(
      'sha256-S9v8mQ0Xba2sG+AEXC4IpdFUM2EX/oRNADEeJ5MpV3s=',
      darkroom.asset_integrity('/app.js', :sha256)
    )

    assert_equal(
      'sha384-2nxTl5wRLPxsDXWEi27WU3OmaXL2BxWbycv+O0ICyA11sCQMbb1K/uREBxvBKaMT',
      darkroom.asset_integrity('/app.js', :sha384)
    )

    assert_equal(
      'sha512-VAhb8yjzGIyuPN8kosvMhu7ix55T8eLHdOqrYNcXwA6rPUlt1/420xdSzl2SNHOp93piKyjcNkQwh2Lw8imrQA==',
      darkroom.asset_integrity('/app.js', :sha512)
    )
  end

  test('#asset_integrity returns sha384 subresource integrity string by default') do
    write_files('/assets/app.js' => "console.log('Hello')")

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)

    assert_equal(
      'sha384-2nxTl5wRLPxsDXWEi27WU3OmaXL2BxWbycv+O0ICyA11sCQMbb1K/uREBxvBKaMT',
      darkroom.asset_integrity('/app.js')
    )
  end

  test('#asset_integrity raises error if algorithm argument is not recognized') do
    write_files('/assets/app.js' => "console.log('Hello')")

    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)

    error = assert_raises(RuntimeError) do
      darkroom.asset_integrity('/app.js', :sha)
    end

    assert_equal('Unrecognized integrity algorithm: sha', error.to_s)
  end

  test('#asset_integrity raises AssetNotFoundError if asset does not exist') do
    darkroom('/assets')
    darkroom.process

    refute_error(darkroom.errors)

    error = assert_raises(Darkroom::AssetNotFoundError) do
      darkroom.asset_integrity('/does-not-exist.js')
    end

    assert_equal('Asset not found: /does-not-exist.js', error.to_s)
  end

  ##########################################################################################################
  ## #dump                                                                                                ##
  ##########################################################################################################

  def setup_dump_dir(with_file: false)
    FileUtils.rm_rf(DUMP_DIR)
    FileUtils.mkdir_p(DUMP_DIR)

    File.write(DUMP_DIR_EXISTING_FILE, 'Existing file...') if with_file
  end

  test('#dump raises error if present from last process run') do
    write_files('/assets/app.js' => "import '/missing.js'")

    darkroom('/assets')
    darkroom.process

    error = assert_raises(Darkroom::ProcessingError) do
      darkroom.dump(DUMP_DIR)
    end

    assert_equal("Errors were encountered while processing assets:\n  /app.js:1: Asset not found: " \
      '/missing.js', error.to_s)
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump creates target directory if it does not exist') do
    write_files(
      '/assets/app.js' => "console.log('Hello')",
      '/assets/app.css' => 'body { background: white; }',
    )

    FileUtils.rm_rf(DUMP_DIR)

    darkroom('/assets')
    darkroom.process
    darkroom.dump(DUMP_DIR)

    assert(File.directory?(DUMP_DIR))
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump writes processed assets to a directory') do
    write_files(
      '/assets/app.js' => "console.log('Hello')",
      '/assets/app.css' => 'body { background: white; }',
    )

    setup_dump_dir

    darkroom('/assets')
    darkroom.process
    darkroom.dump(DUMP_DIR)

    assert_equal(
      darkroom.asset('/app.js').content,
      File.read("#{DUMP_DIR}/app-ef0f76b822009ab847bd6a370e911556.js")
    )

    assert_equal(
      darkroom.asset('/app.css').content,
      File.read("#{DUMP_DIR}/app-c7319c7b3b95111f028f6f4161ebd371.css")
    )
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump only includes entry point assets') do
    write_files(
      '/assets/app.js' => "console.log('Hello')",
      '/assets/components/header.css' => 'header { background: white; }',
    )

    setup_dump_dir

    darkroom('/assets', entries: %r{^/[^/]+$})
    darkroom.process
    darkroom.dump(DUMP_DIR)

    assert_path_exists("#{DUMP_DIR}/app-ef0f76b822009ab847bd6a370e911556.js")
    refute_path_exists("#{DUMP_DIR}/components/header-e84f21b5c4ce60bb92d2e61e2b4d11f1.htx")
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump does not delete anything in target directory by default') do
    write_files('/assets/app.js' => "console.log('Hello')")

    setup_dump_dir(with_file: true)

    darkroom('/assets')
    darkroom.process
    darkroom.dump(DUMP_DIR)

    assert_path_exists(DUMP_DIR_EXISTING_FILE)
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump deletes everything in target directory if `clear` option is true') do
    write_files('/assets/app.js' => "console.log('Hello')")

    setup_dump_dir(with_file: true)

    darkroom('/assets')
    darkroom.process
    darkroom.dump(DUMP_DIR, clear: true)

    refute_path_exists(DUMP_DIR_EXISTING_FILE)
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump does not delete anything in target directory if `clear` option is false') do
    write_files('/assets/app.js' => "console.log('Hello')")

    setup_dump_dir(with_file: true)

    darkroom('/assets')
    darkroom.process
    darkroom.dump(DUMP_DIR, clear: false)

    assert_path_exists(DUMP_DIR_EXISTING_FILE)
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump includes pristine assets by default') do
    write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

    setup_dump_dir

    darkroom('/assets')
    darkroom.process
    darkroom.dump(DUMP_DIR)

    assert_path_exists("#{DUMP_DIR}/robots.txt")
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump includes pristine assets if `include_pristine` option is true') do
    write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

    setup_dump_dir

    darkroom('/assets')
    darkroom.process
    darkroom.dump(DUMP_DIR, include_pristine: true)

    assert_path_exists("#{DUMP_DIR}/robots.txt")
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  test('#dump does not include pristine assets if `include_pristine` option is false') do
    write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

    setup_dump_dir

    darkroom('/assets')
    darkroom.process
    darkroom.dump(DUMP_DIR, include_pristine: false)

    refute_path_exists("#{DUMP_DIR}/robots.txt")
  ensure
    FileUtils.rm_rf(DUMP_DIR)
  end

  ##########################################################################################################
  ## #inspect                                                                                             ##
  ##########################################################################################################

  test('#inspect returns a high-level object info string') do
    write_files(
      '/assets/bad-import.js' => <<~JS,
        import '/does-not-exist.js'

        console.log('Hello')
      JS

      '/assets/bad-imports.js' => <<~JS,
        import '/does-not-exist.js'
        import '/also-does-not-exist.js'

        console.log('Hello')
      JS
    )

    darkroom(
      '/assets',
      hosts: 'https://cdn1.hello.world',
      prefix: '/static',
      pristine: '/hi.txt',
      entries: %r{^/[^/]+$},
      minified: /\.minified\.*/,
      min_process_interval: 1,
    )
    darkroom.process

    assert_inspect('#<Darkroom ' \
      '@entries=[/^\\/[^\\/]+$/], ' \
      '@errors=[' \
        '#<Darkroom::AssetNotFoundError: /bad-import.js:1: Asset not found: /does-not-exist.js>, ' \
        '#<Darkroom::AssetNotFoundError: /bad-imports.js:1: Asset not found: /does-not-exist.js>, ' \
        '#<Darkroom::AssetNotFoundError: /bad-imports.js:2: Asset not found: /also-does-not-exist.js>' \
      '], ' \
      '@hosts=["https://cdn1.hello.world"], ' \
      "@last_processed_at=#{darkroom.instance_variable_get(:@last_processed_at)}, " \
      "@load_paths=[\"#{full_path('/assets')}\"], " \
      '@min_process_interval=1, ' \
      '@minified=[/\\.minified\\.*/], ' \
      '@minify=false, ' \
      '@prefix="/static", ' \
      '@pristine=#<Set: {"/favicon.ico", "/mask-icon.svg", "/humans.txt", "/robots.txt", "/hi.txt"}>, ' \
      '@process_key=1' \
    '>', darkroom)
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def darkroom(*load_paths, **options)
    unless @darkroom && load_paths.empty? && options.empty?
      @darkroom = Darkroom.new(*load_paths.map { |path| full_path(path) }, **options)
    end

    @darkroom
  end
end
