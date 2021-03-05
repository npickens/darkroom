# frozen_string_literal: true

require_relative('test_helper')

class AssetTest < Minitest::Test
  include(TestHelper)

  def self.context
    'Darkroom::Asset'
  end

  ##########################################################################################################
  ## Test #initialize                                                                                     ##
  ##########################################################################################################

  test('#initialize raises SpecNotDefinedError if no spec is defined for a file extension') do
    path = '/app.undefined'
    file = file_for(path)

    error = assert_raises(Darkroom::SpecNotDefinedError) do
      get_asset(path)
    end

    assert_includes(error.inspect, '.undefined')
    assert_includes(error.inspect, file)
  end

  test('#initialize requires compile library if spec has one') do
    Darkroom::Asset.add_spec('.dummy-compile', 'text/dummy-compile', compile_lib: 'dummy_compile')

    refute(defined?(DummyCompile), 'Expected DummyCompile to be undefined when an asset of that type has '\
      'not be initialized yet.')

    get_asset('/app.dummy-compile')

    assert(defined?(DummyCompile), 'Expected DummyCompile to be defined.')
  end

  test('#initialize requires minify library if spec has one and minification is enabled') do
    Darkroom::Asset.add_spec('.dummy-minify', 'text/dummy-minify', minify_lib: 'dummy_minify')

    get_asset('/app.dummy-minify')
    refute(defined?(DummyMinify), 'Expected DummyMinify to be undefined when minification is not enabled.')

    get_asset('/app.dummy-minify', minify: true)
    assert(defined?(DummyMinify), 'Expected DummyMinify to be defined.')
  end

  test('#initialize raises MissingLibraryError if compile library is not available') do
    Darkroom::Asset.add_spec('.bad-compile', 'text/bad-compile', compile_lib: 'bad_compile')

    error = assert_raises(Darkroom::MissingLibraryError) do
      get_asset('/app.bad-compile')
    end

    assert_includes(error.inspect, Darkroom::Asset.spec('.bad-compile').compile_lib)
  ensure
    Darkroom::Asset.class_variable_get(:@@specs).delete('.bad-compile')
  end

  test('#initialize raises MissingLibraryError if minification is enabled and minify library is missing') do
    Darkroom::Asset.add_spec('.bad-minify', 'text/bad-minify', minify_lib: 'bad_minify')

    begin
      get_asset('/app.bad-minify')
    rescue Darkroom::MissingLibraryError => e
      assert(false, 'Expected minify library to not be required when minification is not enabled')
    end

    error = assert_raises(Darkroom::MissingLibraryError) do
      get_asset('/app.bad-minify', minify: true)
    end

    assert_includes(error.inspect, Darkroom::Asset.spec('.bad-minify').minify_lib)
  ensure
    Darkroom::Asset.class_variable_get(:@@specs).delete('.bad-minify')
  end

  ##########################################################################################################
  ## Test #process                                                                                        ##
  ##########################################################################################################

  test('#process compiles content if compilation is part of spec') do
    path = '/template.htx'
    file = file_for(path)
    asset = get_asset(path)

    asset.process(Time.now.to_f)

    assert_equal("[HTX.compile(#{path.inspect}, #{File.read(file).inspect})]", asset.content)
  end

  test('#process minifies content if minification is part of spec and minification is enabled') do
    [
      ['/app.css', 'CSSminify.compress'],
      ['/app.js', 'Uglifier.compile'],
      ['/template.htx', 'Uglifier.compile'],
    ].each do |path, meth|
      asset = get_asset(path)
      file = file_for(asset.path)

      asset.process(Time.now.to_f)
      content = asset.content

      asset = get_asset(path, minify: true)
      asset.process(Time.now.to_f)

      assert_equal("[#{meth}(#{content.inspect})]", asset.content)
    end
  end

  test('#process merges dependencies with own content') do
    imported = get_asset('/app.js')
    imported_own_content = imported.send(:own_content)

    asset = get_asset('/good-import.js', {'/app.js' => imported})
    asset_own_content = asset.send(:own_content)

    asset.process(Time.now.to_f)

    assert_equal(imported_own_content, asset.content[0...imported_own_content.size])
    assert_equal(asset_own_content, asset.content[imported_own_content.size..-1])
  end

  test('#process gracefully handles asset file being deleted on disk') do
    asset = get_asset('/deleted.js')
    asset.process(Time.now.to_f)

    assert_empty(asset.content)
  end

  test('#process does not register any errors if successful') do
    asset = get_asset(minify: true)
    asset.process(Time.now.to_f)

    assert_nil(asset.error)
    assert_empty(asset.errors)
  end

  test('#process registers an error when a dependency is not found') do
    asset = get_asset('/bad-import.js')
    asset.process(Time.now.to_f)

    assert_equal(1, asset.errors.size)
    assert_instance_of(Darkroom::AssetNotFoundError, asset.errors.first)
    assert_includes(asset.errors.first.inspect, '/bad-import.js')
    assert_includes(asset.errors.first.inspect, '/does-not-exist.js')

    assert_instance_of(Darkroom::ProcessingError, asset.error)
    assert_equal(1, asset.error.size)
    assert_equal(asset.errors, asset.error.instance_variable_get(:@errors))
  end

  test('#process registers an error when compilation raises an exception') do
    asset = get_asset('/template.htx')

    HTX.stub(:compile, -> (*args) { raise('[HTX Error]') }) do
      asset.process(Time.now.to_f)
    end

    assert(asset.error)
    assert_includes(asset.error.message, '[HTX Error]')
  end

  test('#process registers an error when minification raises an exception') do
    asset = get_asset('/app.js', minify: true)

    Uglifier.stub(:compile, -> (*args) { raise('[Uglifier Error]') }) do
      asset.process(Time.now.to_f)
    end

    assert(asset.error)
    assert_includes(asset.error.message, '[Uglifier Error]')
  end

  test('#process accumulates multiple errors') do
    asset = get_asset('/bad-imports.js', minify: true)

    Uglifier.stub(:compile, -> (*args) { raise('[Uglifier Error]') }) do
      asset.process(Time.now.to_f)
    end

    assert_equal(3, asset.errors.size)

    assert_instance_of(Darkroom::AssetNotFoundError, asset.errors[0])
    assert_instance_of(Darkroom::AssetNotFoundError, asset.errors[1])
    assert_instance_of(RuntimeError, asset.errors[2])

    assert_includes(asset.errors[0].inspect, '/bad-imports.js')
    assert_includes(asset.errors[0].inspect, '/does-not-exist.js')

    assert_includes(asset.errors[1].inspect, '/bad-imports.js')
    assert_includes(asset.errors[1].inspect, '/also-does-not-exist.js')

    assert_includes(asset.errors[2].inspect, '[Uglifier Error]')

    assert_instance_of(Darkroom::ProcessingError, asset.error)
    assert_equal(3, asset.error.size)
    assert_equal(asset.errors, asset.error.instance_variable_get(:@errors))
  end

  ##########################################################################################################
  ## Test #content_type                                                                                   ##
  ##########################################################################################################

  test('#content_type returns the HTTP MIME type string for the asset') do
    assert_equal('text/css', get_asset('/app.css').content_type)
    assert_equal('text/html', get_asset('/index.html').content_type)
    assert_equal('application/javascript', get_asset('/template.htx').content_type)
    assert_equal('image/x-icon', get_asset('/favicon.ico').content_type)
    assert_equal('application/javascript', get_asset('/app.js').content_type)
    assert_equal('image/jpeg', get_asset('/photo.jpg').content_type)
    assert_equal('image/png', get_asset('/graphic.png').content_type)
    assert_equal('image/svg+xml', get_asset('/graphic.svg').content_type)
    assert_equal('text/plain', get_asset('/robots.txt').content_type)
    assert_equal('font/woff', get_asset('/font.woff').content_type)
    assert_equal('font/woff2', get_asset('/font.woff2').content_type)
  end

  ##########################################################################################################
  ## Test #headers                                                                                        ##
  ##########################################################################################################

  test('#headers includes Content-Type header') do
    Darkroom::Asset.extensions.each do |extension|
      asset = get_asset("/hello#{extension}")
      assert_equal(asset.content_type, asset.headers['Content-Type'])
    end
  end

  test('#headers includes Cache-Control header if :versioned is not specified') do
    asset = get_asset
    headers = asset.headers

    assert_equal('public, max-age=31536000', headers['Cache-Control'])
    assert_nil(headers['ETag'])
  end

  test('#headers includes Cache-Control header if :versioned is true') do
    asset = get_asset
    asset.process(Time.now.to_f)

    headers = asset.headers(versioned: true)

    assert_equal('public, max-age=31536000', headers['Cache-Control'])
    assert_nil(headers['ETag'])
  end

  test('#headers includes ETag header if :versioned is false') do
    asset = get_asset
    asset.process(Time.now.to_f)

    headers = asset.headers(versioned: false)

    assert_equal('"25f290825cb44d4cf57632abfa82c37e"', headers['ETag'])
    assert_nil(headers['Cache-Control'])
  end

  ##########################################################################################################
  ## Test #integrity                                                                                      ##
  ##########################################################################################################

  test('#integrity returns subresource integrity string according to algorithm argument') do
    asset = get_asset
    asset.process(Time.now.to_f)

    assert_equal(JS_ASSET_SHA256, asset.integrity(:sha256))
    assert_equal(JS_ASSET_SHA384, asset.integrity(:sha384))
    assert_equal(JS_ASSET_SHA512, asset.integrity(:sha512))
  end

  test('#integrity returns sha384 subresource integrity string by default') do
    asset = get_asset
    asset.process(Time.now.to_f)

    assert_equal(JS_ASSET_SHA384, asset.integrity)
  end

  test('#integrity raises error if algorithm argument is not recognized') do
    asset = get_asset
    asset.process(Time.now.to_f)

    assert_raises(RuntimeError) do
      asset.integrity(:sha)
    end
  end

  ##########################################################################################################
  ## Test #internal?                                                                                      ##
  ##########################################################################################################

  test('#internal? returns true if asset was initialized as internal') do
    asset = get_asset(internal: true)

    assert(asset.internal?)
  end

  test('#internal? returns false if asset was initialized as non-internal') do
    asset = get_asset(internal: false)

    refute(asset.internal?)
  end

  test('#internal? returns false if asset was initialized without specifying internal status') do
    asset = get_asset

    refute(asset.internal?)
  end

  ##########################################################################################################
  ## Test #error?                                                                                         ##
  ##########################################################################################################

  test('#error? returns false if there were no errors during processing') do
    asset = get_asset
    asset.process(Time.now.to_f)

    refute(asset.error?)
  end

  test('#error? returns true if there were one or more errors during processing') do
    asset = get_asset('/bad-import.js')
    asset.process(Time.now.to_f)
    assert(asset.error?)
  end

  ##########################################################################################################
  ## Test #inspect                                                                                        ##
  ##########################################################################################################

  test('#inspect returns a high-level object info string') do
    asset = get_asset('/bad-import.js', prefix: '/static')
    file = file_for(asset.path)

    asset.process(Time.now.to_f)

    assert_equal('#<Darkroom::Asset: '\
      '@errors=[#<Darkroom::AssetNotFoundError: Asset not found (referenced from /bad-import.js:1): '\
        '/does-not-exist.js>], '\
      '@extension=".js", '\
      "@file=\"#{file}\", "\
      '@fingerprint="afa0a5ffe7423f4b568f19a39b53b122", '\
      '@internal=false, '\
      '@minify=false, '\
      "@mtime=#{File.mtime(file).inspect}, "\
      '@path="/bad-import.js", '\
      '@path_unversioned="/static/bad-import.js", '\
      '@path_versioned="/static/bad-import-afa0a5ffe7423f4b568f19a39b53b122.js", '\
      '@prefix="/static"'\
    '>'.split(INSPECT_SPLIT).join(INSPECT_JOIN), asset.inspect.split(INSPECT_SPLIT).join(INSPECT_JOIN))
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def get_asset(*args, **options)
    path = args.first.kind_of?(String) ? args.first : JS_ASSET_PATH
    file = file_for(path)
    manifest = args.last.kind_of?(Hash) ? args.last : {}

    Darkroom::Asset.new(path, file, manifest, **options)
  end

  def file_for(path)
    File.join(path.start_with?('/bad-') ? BAD_ASSET_DIR : ASSET_DIR, path)
  end
end
