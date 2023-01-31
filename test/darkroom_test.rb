# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('test_helper')

class DarkroomTest < Minitest::Test
  include(TestHelper)

  DUMP_DIR = File.join(TMP_DIR, 'dump').freeze
  DUMP_DIR_EXISTING_FILE = File.join(DUMP_DIR, 'existing.txt').freeze

  context(Darkroom) do
    ########################################################################################################
    ## #process                                                                                           ##
    ########################################################################################################

    context('#process') do
      test('skips processing if minimum process interval has not elapsed since last call') do
        write_files('/assets/app.js' => "console.log('Hello')")

        darkroom('/assets', min_process_interval: 2)
        darkroom.process

        write_files('/assets/tmp.txt' => 'Temporary...')
        darkroom.process

        assert(darkroom.asset('/app.js'))
        assert_nil(darkroom.asset('/tmp.txt'))
      end

      test('skips processing if another thread is currently processing') do
        mutex_mock = Minitest::Mock.new
        def mutex_mock.locked?() (@locked_calls = (@locked_calls || 0) + 1) == 2 end
        def mutex_mock.synchronize(&block) block.call end

        Mutex.stub(:new, mutex_mock) do
          write_files('/assets/app.js' => "console.log('Hello')")

          darkroom('/assets', min_process_interval: 0)
          darkroom.process

          write_files('/assets/tmp.txt' => 'Temporary...')
          darkroom.process
        end

        assert(darkroom.asset('/app.js'))
        assert_nil(darkroom.asset('/tmp.txt'))
      end

      test('registers InvalidPathError if an asset path contains one or more disallowed character') do
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

        paths.each.with_index do |path, i|
          assert_kind_of(Darkroom::InvalidPathError, darkroom.errors[i])
          assert_equal("Asset path contains one or more invalid characters ('\"`=<>? ): #{path}",
            darkroom.errors[i].to_s)
        end
      end

      test('registers DuplicateAssetError if an asset with the same path is in multiple load paths') do
        write_files(
          '/assets/app.js' => "console.log('Hello')",
          '/other-assets/app.js' => "console.log('Hello again')",
        )

        darkroom('/assets', '/other-assets')
        darkroom.process

        assert_kind_of(Darkroom::DuplicateAssetError, darkroom.errors.first)
        assert_equal("Asset file exists in both #{full_path('/assets')} and "\
          "#{full_path('/other-assets')}: /app.js", darkroom.errors.first.to_s)
      end
    end

    ########################################################################################################
    ## #process!                                                                                          ##
    ########################################################################################################

    context('#process!') do
      test('raises ProcessingError if there were one or more errors during processing') do
        write_files(
          '/assets/bad-imports.js' => <<~EOS,
            import '/does-not-exist.js'
            import '/also-does-not-exist.js'

            console.log('Hello')
          EOS
        )

        error = assert_raises(Darkroom::ProcessingError) do
          darkroom('/assets')
          darkroom.process!
        end

        assert_equal(
          "Errors were encountered while processing assets:\n"\
          "  /bad-imports.js:1: Asset not found: /does-not-exist.js\n"\
          "  /bad-imports.js:2: Asset not found: /also-does-not-exist.js",
          error.to_s
        )
      end
    end

    ########################################################################################################
    ## #error?                                                                                            ##
    ########################################################################################################

    context('#error?') do
      test('returns false if there were no errors during processing') do
        write_files('/assets/app.js' => "console.log('Hello')")

        darkroom('/assets')
        darkroom.process

        refute(darkroom.error?)
      end

      test('returns true if there were one or more errors during processing') do
        write_files(
          '/assets/bad-import.js' => <<~EOS,
            import '/does-not-exist.js'

            console.log('Hello')
          EOS
        )

        darkroom('/assets')
        darkroom.process

        assert(darkroom.error?)
      end
    end

    ########################################################################################################
    ## #asset                                                                                             ##
    ########################################################################################################

    context('#asset') do
      test('returns nil if asset does not exist') do
        darkroom('/assets')
        darkroom.process

        assert_nil(darkroom.asset('/does-not-exist.js'))
      end

      test('returns asset for unversioned path') do
        content = "console.log('Hello')"
        write_files('/assets/app.js' => content)

        darkroom('/assets')
        darkroom.process

        asset = darkroom.asset('/app.js')

        assert(asset)
        assert_equal(content, asset.content)
      end

      test('returns asset for versioned path') do
        content = "console.log('Hello')"
        write_files('/assets/app.js' => content)

        darkroom('/assets')
        darkroom.process

        asset = darkroom.asset('/app-ef0f76b822009ab847bd6a370e911556.js')

        assert(asset)
        assert_equal(content, asset.content)
      end

      test('only returns asset if path includes prefix when a prefix is configured and asset is not '\
          'pristine') do
        write_files('/assets/app.js' => "console.log('Hello')")

        darkroom('/assets', prefix: '/static')
        darkroom.process

        assert(darkroom.asset('/static/app.js'))
        assert(darkroom.asset('/static/app-ef0f76b822009ab847bd6a370e911556.js'))

        assert_nil(darkroom.asset('/app.js'))
        assert_nil(darkroom.asset('/app-aec92e09ce672c46c094c95b1208cd09.js'))
      end

      test('only returns asset if path excludes prefix when a prefix is configured and asset is '\
          'pristine') do
        write_files('/assets/pristine.txt' => 'Hello')

        darkroom('/assets', prefix: '/static', pristine: '/pristine.txt')
        darkroom.process

        assert_nil(darkroom.asset('/static/pristine.txt'))
        assert_nil(darkroom.asset('/static/pristine-8b1a9953c4611296a827abf8c47804d7.txt'))

        assert(darkroom.asset('/pristine.txt'))
        assert(darkroom.asset('/pristine-8b1a9953c4611296a827abf8c47804d7.txt'))
      end

      test('returns nil if asset is internal') do
        write_files('/assets/components/header.htx' => '<header>${this.title}</header>')

        darkroom('/assets', internal_pattern: /^\/components\/.*$/)
        darkroom.process

        assert_nil(darkroom.asset('/components/header.htx'))
      end

      test('returns asset if path matches internal pattern but is also pristine') do
        write_files('/assets/pristine.txt' => 'Hello')

        darkroom('/assets', internal_pattern: /.*/, pristine: '/pristine.txt')
        darkroom.process

        assert(darkroom.asset('/pristine.txt'))
      end
    end

    ########################################################################################################
    ## #asset_path                                                                                        ##
    ########################################################################################################

    context('#asset_path') do
      test('raises AssetNotFoundError if asset does not exist') do
        darkroom('/assets')
        darkroom.process

        error = assert_raises(Darkroom::AssetNotFoundError) do
          darkroom.asset_path('/does-not-exist.js')
        end

        assert_equal('Asset not found: /does-not-exist.js', error.to_s)
      end

      test('returns versioned path by default if asset is not pristine') do
        write_files('/assets/app.js' => "console.log('Hello')")

        darkroom('/assets')
        darkroom.process

        assert_equal('/app-ef0f76b822009ab847bd6a370e911556.js', darkroom.asset_path('/app.js'))
      end

      test('returns unversioned path by default if asset is pristine') do
        write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

        darkroom('/assets')
        darkroom.process

        assert_equal('/robots.txt', darkroom.asset_path('/robots.txt'))
      end

      test('returns versioned asset path if `versioned` option is true') do
        write_files(
          '/assets/app.js' => "console.log('Hello')",
          '/assets/robots.txt' => "User-agent: *\nDisallow:",
        )

        darkroom('/assets')
        darkroom.process

        assert_equal('/app-ef0f76b822009ab847bd6a370e911556.js', darkroom.asset_path('/app.js',
          versioned: true))
        assert_equal('/robots-50d8a018e8ae96732c8a2ba663c61d4e.txt', darkroom.asset_path('/robots.txt',
          versioned: true))
      end

      test('returns unversioned asset path if `versioned` option is false') do
        write_files(
          '/assets/app.js' => "console.log('Hello')",
          '/assets/robots.txt' => "User-agent: *\nDisallow:",
        )

        darkroom('/assets')
        darkroom.process

        assert_equal('/app.js', darkroom.asset_path('/app.js', versioned: false))
        assert_equal('/robots.txt', darkroom.asset_path('/robots.txt', versioned: false))
      end

      test('includes a round-robin selected host if any hosts are configured') do
        write_files(
          '/assets/app.js' => "console.log('Hello')",
          '/assets/app.css' => 'body { background: white; }',
        )

        host = 'https://cdn1.darkroom'
        hosts = %w[https://cdn1.darkroom https://cdn2.darkroom https://cdn3.darkroom]

        darkroom('/assets', host: host)
        darkroom.process

        assert_equal("#{host}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))
        assert_equal("#{host}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))

        darkroom('/assets', hosts: hosts)
        darkroom.process

        assert_equal("#{hosts[0]}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))
        assert_equal("#{hosts[1]}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))
        assert_equal("#{hosts[2]}/app-c7319c7b3b95111f028f6f4161ebd371.css",
          darkroom.asset_path('/app.css'))
        assert_equal("#{hosts[0]}/app-ef0f76b822009ab847bd6a370e911556.js", darkroom.asset_path('/app.js'))
      end

      test('includes prefix if one is configured and asset is not pristine') do
        write_files('/assets/app.js' => "console.log('Hello')")

        darkroom('/assets', prefix: '/static')
        darkroom.process

        assert_equal('/static/app-ef0f76b822009ab847bd6a370e911556.js', darkroom.asset_path('/app.js'))
      end

      test('does not include prefix if one is configured and asset is pristine') do
        write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

        darkroom('/assets', prefix: '/static')
        darkroom.process

        assert_equal('/robots.txt', darkroom.asset_path('/robots.txt'))
      end
    end

    ########################################################################################################
    ## #asset_integrity                                                                                   ##
    ########################################################################################################

    context('#asset_integrity') do
      test('returns subresource integrity string according to algorithm argument') do
        write_files('/assets/app.js' => "console.log('Hello')")

        darkroom('/assets')
        darkroom.process

        assert_equal('sha256-S9v8mQ0Xba2sG+AEXC4IpdFUM2EX/oRNADEeJ5MpV3s=',
          darkroom.asset_integrity('/app.js', :sha256))
        assert_equal('sha384-2nxTl5wRLPxsDXWEi27WU3OmaXL2BxWbycv+O0ICyA11sCQMbb1K/uREBxvBKaMT',
          darkroom.asset_integrity('/app.js', :sha384))
        assert_equal('sha512-VAhb8yjzGIyuPN8kosvMhu7ix55T8eLHdOqrYNcXwA6rPUlt1/420xdSzl2SNHOp93piKyjcNkQwh'\
          '2Lw8imrQA==', darkroom.asset_integrity('/app.js', :sha512))
      end

      test('returns sha384 subresource integrity string by default') do
        write_files('/assets/app.js' => "console.log('Hello')")

        darkroom('/assets')
        darkroom.process

        assert_equal('sha384-2nxTl5wRLPxsDXWEi27WU3OmaXL2BxWbycv+O0ICyA11sCQMbb1K/uREBxvBKaMT',
          darkroom.asset_integrity('/app.js'))
      end

      test('raises error if algorithm argument is not recognized') do
        write_files('/assets/app.js' => "console.log('Hello')")

        darkroom('/assets')
        darkroom.process

        error = assert_raises(RuntimeError) do
          darkroom.asset_integrity('/app.js', :sha)
        end

        assert_equal('Unrecognized integrity algorithm: sha', error.to_s)
      end

      test('raises AssetNotFoundError if asset does not exist') do
        darkroom('/assets')
        darkroom.process

        error = assert_raises(Darkroom::AssetNotFoundError) do
          darkroom.asset_integrity('/does-not-exist.js')
        end

        assert_equal('Asset not found: /does-not-exist.js', error.to_s)
      end
    end

    ########################################################################################################
    ## #dump                                                                                              ##
    ########################################################################################################

    def setup_dump_dir(with_file: false)
      FileUtils.rm_rf(DUMP_DIR)
      FileUtils.mkdir_p(DUMP_DIR)

      File.write(DUMP_DIR_EXISTING_FILE, 'Existing file...') if with_file
    end

    context('#dump') do
      test('creates target directory if it does not exist') do
        write_files(
          '/assets/app.js' => "console.log('Hello')",
          '/assets/app.css' => 'body { background: white; }',
        )

        FileUtils.rm_rf(DUMP_DIR)

        darkroom('/assets')
        darkroom.process
        darkroom.dump(DUMP_DIR) rescue nil

        assert(File.directory?(DUMP_DIR))
      ensure
        FileUtils.rm_rf(DUMP_DIR)
      end

      test('writes processed assets to a directory') do
        write_files(
          '/assets/app.js' => "console.log('Hello')",
          '/assets/app.css' => 'body { background: white; }',
        )

        setup_dump_dir

        darkroom('/assets')
        darkroom.process
        darkroom.dump(DUMP_DIR)

        assert_equal(darkroom.asset('/app.js').content,
          File.read("#{DUMP_DIR}/app-ef0f76b822009ab847bd6a370e911556.js"))
        assert_equal(darkroom.asset('/app.css').content,
          File.read("#{DUMP_DIR}/app-c7319c7b3b95111f028f6f4161ebd371.css"))
      ensure
        FileUtils.rm_rf(DUMP_DIR)
      end

      test('does not include internal assets') do
        write_files(
          '/assets/app.js' => "console.log('Hello')",
          '/assets/components/header.htx' => '<header>${this.title}</header>',
        )

        setup_dump_dir

        darkroom('/assets', internal_pattern: /^\/components\/.*$/)
        darkroom.process
        darkroom.dump(DUMP_DIR)

        assert(File.exists?("#{DUMP_DIR}/app-ef0f76b822009ab847bd6a370e911556.js"))
        refute(File.exists?("#{DUMP_DIR}/components/header-e84f21b5c4ce60bb92d2e61e2b4d11f1.htx"))
      ensure
        FileUtils.rm_rf(DUMP_DIR)
      end

      test('does not delete anything in target directory by default') do
        write_files('/assets/app.js' => "console.log('Hello')")

        setup_dump_dir(with_file: true)

        darkroom('/assets')
        darkroom.process
        darkroom.dump(DUMP_DIR)

        assert(File.exists?(DUMP_DIR_EXISTING_FILE))
      ensure
        FileUtils.rm_rf(DUMP_DIR)
      end

      test('deletes everything in target directory if `clear` option is true') do
        write_files('/assets/app.js' => "console.log('Hello')")

        setup_dump_dir(with_file: true)

        darkroom('/assets')
        darkroom.process
        darkroom.dump(DUMP_DIR, clear: true)

        refute(File.exists?(DUMP_DIR_EXISTING_FILE))
      ensure
        FileUtils.rm_rf(DUMP_DIR)
      end

      test('does not delete anything in target directory if `clear` option is false') do
        write_files('/assets/app.js' => "console.log('Hello')")

        setup_dump_dir(with_file: true)

        darkroom('/assets')
        darkroom.process
        darkroom.dump(DUMP_DIR, clear: false)

        assert(File.exists?(DUMP_DIR_EXISTING_FILE))
      ensure
        FileUtils.rm_rf(DUMP_DIR)
      end

      test('includes pristine assets by default') do
        write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

        setup_dump_dir

        darkroom('/assets')
        darkroom.process
        darkroom.dump(DUMP_DIR)

        assert(File.exists?("#{DUMP_DIR}/robots.txt"))
      ensure
        FileUtils.rm_rf(DUMP_DIR)
      end

      test('includes pristine assets if `include_pristine` option is true') do
        write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

        setup_dump_dir

        darkroom('/assets')
        darkroom.process
        darkroom.dump(DUMP_DIR, include_pristine: true)

        assert(File.exists?("#{DUMP_DIR}/robots.txt"))
      ensure
        FileUtils.rm_rf(DUMP_DIR)
      end

      test('does not include pristine assets if `include_pristine` option is false') do
        write_files('/assets/robots.txt' => "User-agent: *\nDisallow:")

        setup_dump_dir

        darkroom('/assets')
        darkroom.process
        darkroom.dump(DUMP_DIR, include_pristine: false)

        refute(File.exists?("#{DUMP_DIR}/robots.txt"))
      ensure
        FileUtils.rm_rf(DUMP_DIR)
      end
    end

    ########################################################################################################
    ## #inspect                                                                                           ##
    ########################################################################################################

    context('#inspect') do
      test('returns a high-level object info string') do
        write_files(
          '/assets/bad-import.js' => <<~EOS,
            import '/does-not-exist.js'

            console.log('Hello')
          EOS

          '/assets/bad-imports.js' => <<~EOS,
            import '/does-not-exist.js'
            import '/also-does-not-exist.js'

            console.log('Hello')
          EOS
        )

        darkroom('/assets',
          hosts: 'https://cdn1.hello.world',
          prefix: '/static',
          pristine: '/hi.txt',
          minified_pattern: /\.minified\.*/,
          internal_pattern: /^\/private\//,
          min_process_interval: 1,
        )
        darkroom.process

        assert_inspect('#<Darkroom: '\
          '@errors=['\
            '#<Darkroom::AssetNotFoundError: /bad-import.js:1: Asset not found: /does-not-exist.js>, '\
            '#<Darkroom::AssetNotFoundError: /bad-imports.js:1: Asset not found: /does-not-exist.js>, '\
            '#<Darkroom::AssetNotFoundError: /bad-imports.js:2: Asset not found: /also-does-not-exist.js>'\
          '], '\
          '@hosts=["https://cdn1.hello.world"], '\
          '@internal_pattern=/^\\/private\\//, '\
          "@last_processed_at=#{darkroom.instance_variable_get(:@last_processed_at)}, "\
          "@load_paths=[\"#{full_path('/assets')}\"], "\
          '@min_process_interval=1, '\
          '@minified_pattern=/\\.minified\\.*/, '\
          '@minify=false, '\
          '@prefix="/static", '\
          '@pristine=#<Set: {"/favicon.ico", "/mask-icon.svg", "/humans.txt", "/robots.txt", "/hi.txt"}>, '\
          '@process_key=1'\
        '>', darkroom)
      end
    end
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def darkroom(*load_paths, **options)
    unless @@darkroom && load_paths.empty? && options.empty?
      @@darkroom = Darkroom.new(*load_paths.map { |path| full_path(path) }, **options)
    end

    @@darkroom
  end
end
