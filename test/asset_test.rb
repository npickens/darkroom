# frozen_string_literal: true

require_relative('test_helper')

class AssetTest < Minitest::Test
  include(TestHelper)

  def self.context
    'Darkroom::Asset'
  end

  ##########################################################################################################
  ## Hooks                                                                                                ##
  ##########################################################################################################

  def setup
    @@darkroom = DarkroomMock.new
  end

  ##########################################################################################################
  ## Test #initialize                                                                                     ##
  ##########################################################################################################

  test('#initialize raises UnrecognizedExtensionError if file extension is not registered') do
    error = assert_raises(Darkroom::UnrecognizedExtensionError) do
      new_asset('/app.undefined')
    end

    assert_equal('File extension not recognized: /app.undefined', error.to_s)
  end

  test('#initialize requires compile library if spec has one') do
    Darkroom::Asset.add_spec('.dummy-compile', 'text/dummy-compile', compile_lib: 'dummy_compile')

    refute(defined?(DummyCompile), 'Expected DummyCompile to be undefined before asset is initialized.')
    new_asset('/app.dummy-compile')
    assert(defined?(DummyCompile), 'Expected DummyCompile to be defined after asset is initialized.')
  ensure
    Darkroom::Asset.class_variable_get(:@@specs).delete('.dummy-compile')
  end

  test('#initialize requires minify library if spec has one and minification is enabled') do
    Darkroom::Asset.add_spec('.dummy-minify', 'text/dummy-minify', minify_lib: 'dummy_minify')

    new_asset('/app.dummy-minify')
    refute(defined?(DummyMinify), 'Expected DummyMinify to be undefined when minification is not enabled.')

    new_asset('/app.dummy-minify', minify: true)
    assert(defined?(DummyMinify), 'Expected DummyMinify to be defined when minification is enabled.')
  ensure
    Darkroom::Asset.class_variable_get(:@@specs).delete('.dummy-minify')
  end

  test('#initialize raises MissingLibraryError if compile library is not available') do
    Darkroom::Asset.add_spec('.bad-compile', 'text/bad-compile', compile_lib: 'bad_compile')

    error = assert_raises(Darkroom::MissingLibraryError) do
      new_asset('/app.bad-compile')
    end

    assert_equal('Cannot compile .bad-compile file(s): bad_compile library not available [hint: try '\
      'adding gem(\'bad_compile\') to your Gemfile]', error.to_s)
  ensure
    Darkroom::Asset.class_variable_get(:@@specs).delete('.bad-compile')
  end

  test('#initialize raises MissingLibraryError if minification is enabled and minify library is missing') do
    Darkroom::Asset.add_spec('.bad-minify', 'text/bad-minify', minify_lib: 'bad_minify')

    begin
      new_asset('/app.bad-minify')
    rescue Darkroom::MissingLibraryError => e
      assert(false, 'Expected minify library to not be required when minification is not enabled')
    end

    error = assert_raises(Darkroom::MissingLibraryError) do
      new_asset('/app.bad-minify', minify: true)
    end

    assert_equal('Cannot minify .bad-minify file(s): bad_minify library not available [hint: try adding '\
      'gem(\'bad_minify\') to your Gemfile]', error.to_s)
  ensure
    Darkroom::Asset.class_variable_get(:@@specs).delete('.bad-minify')
  end

  ##########################################################################################################
  ## Test #process                                                                                        ##
  ##########################################################################################################

  test('#process compiles content if compilation is part of spec') do
    path = '/template.htx'
    content = '<div>${this.hello}</div>'
    asset = new_asset(path, content)

    HTX.stub(:compile, ->(*args) do
      assert_equal(path, args[0])
      assert_equal(content, args[1])

      '[compiled]'
    end) do
      asset.process
    end

    assert_equal('[compiled]', asset.content)
  end

  test('#process minifies content if implemented in spec and minification is enabled') do
    content = 'body { background: white; }'
    asset = new_asset('/app.css', content, minify: true)

    SassC::Engine.stub(:new, ->(*args) do
      assert_equal(content, args[0])
      assert_equal({style: :compressed}, args[1])

      sassc_mock = Minitest::Mock.new
      def sassc_mock.render() '[minified]' end

      sassc_mock
    end) do
      asset.process
    end

    assert_equal('[minified]', asset.content)
  end

  test('#process merges dependencies with own content') do
    import_content = "console.log('Import')"
    asset_body = "console.log('App')"

    import = new_asset('/import.js', import_content)
    asset = new_asset('/app.js', "import '/import.js'\n\n#{asset_body}")

    asset.process

    assert_equal(import_content, asset.content[0...import_content.size])
    assert_equal(asset_body, asset.content[-asset_body.size..-1])
  end

  test('#process gracefully handles asset file being deleted on disk') do
    asset = new_asset('/deleted.js')
    asset.process

    assert_empty(asset.content)
  end

  test('#process does not register any errors if successful') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    assert_nil(asset.error)
    assert_empty(asset.errors)
  end

  test('#process registers an error when an import is not found') do
    content = <<~EOS
      import '/does-not-exist.js'

      console.log('Hello')
    EOS

    asset = new_asset('/bad-import.js', content)
    asset.process

    assert_equal(1, asset.errors.size)
    assert_kind_of(Darkroom::AssetNotFoundError, asset.errors.first)
    assert_equal('/bad-import.js:1: Asset not found: /does-not-exist.js', asset.errors.first.to_s)

    assert_kind_of(Darkroom::ProcessingError, asset.error)
    assert_equal(1, asset.error.size)
    assert_equal(asset.errors, asset.error.instance_variable_get(:@errors))
  end

  test('#process registers an error when compilation raises an exception') do
    asset = new_asset('/template.htx', '<div>${this.hello}</div>')

    HTX.stub(:compile, ->(*) { raise('[HTX Error]') }) do
      asset.process
    end

    assert(asset.error)
    assert_equal(1, asset.errors.size)
    assert_equal('[HTX Error]', asset.errors.first.to_s)
  end

  test('#process registers an error when minification raises an exception') do
    asset = new_asset('/app.js', "console.log('Hello')", minify: true)

    Uglifier.stub(:compile, ->(*) { raise('[Uglifier Error]') }) do
      asset.process
    end

    assert(asset.error)
    assert_equal(1, asset.errors.size)
    assert_equal('[Uglifier Error]', asset.errors.first.to_s)
  end

  test('#process accumulates multiple errors') do
    content = <<~EOS
      import '/does-not-exist.js'
      import '/also-does-not-exist.js'

      console.log('Hello')
    EOS
    asset = new_asset('/bad-imports.js', content, minify: true)

    Uglifier.stub(:compile, ->(*) { raise('[Uglifier Error]') }) do
      asset.process
    end

    assert_equal(3, asset.errors.size)

    assert_kind_of(Darkroom::AssetNotFoundError, asset.errors[0])
    assert_kind_of(Darkroom::AssetNotFoundError, asset.errors[1])
    assert_kind_of(RuntimeError, asset.errors[2])

    assert_equal('/bad-imports.js:1: Asset not found: /does-not-exist.js', asset.errors[0].to_s)
    assert_equal('/bad-imports.js:2: Asset not found: /also-does-not-exist.js', asset.errors[1].to_s)
    assert_equal('[Uglifier Error]', asset.errors[2].to_s)

    assert_kind_of(Darkroom::ProcessingError, asset.error)
    assert_equal(3, asset.error.size)
    assert_equal(asset.errors, asset.error.instance_variable_get(:@errors))
  end

  test('#process handles circular dependencies') do
    asset1 = new_asset('/circular1.css', "@import '/circular2.css';\n\n.circular1 { }")
    asset2 = new_asset('/circular2.css', "@import '/circular3.css';\n\n.circular2 { }")
    asset3 = new_asset('/circular3.css', "@import '/circular1.css';\n\n.circular3 { }")

    asset1.process

    refute(asset1.error)
    refute(asset2.error)
    refute(asset3.error)

    assert(asset1.content.start_with?(asset3.send(:own_content)))
    assert(asset2.content.start_with?(asset1.send(:own_content)))
    assert(asset3.content.start_with?(asset2.send(:own_content)))
  end

  ##########################################################################################################
  ## Test #content_type                                                                                   ##
  ##########################################################################################################

  test('#content_type returns the HTTP MIME type string for the asset') do
    assert_equal('text/css',         new_asset('/app.css').content_type)
    assert_equal('text/html',        new_asset('/index.htm').content_type)
    assert_equal('text/html',        new_asset('/index.html').content_type)
    assert_equal('text/javascript',  new_asset('/template.htx').content_type)
    assert_equal('image/x-icon',     new_asset('/favicon.ico').content_type)
    assert_equal('text/javascript',  new_asset('/app.js').content_type)
    assert_equal('image/jpeg',       new_asset('/photo.jpg').content_type)
    assert_equal('image/jpeg',       new_asset('/photo.jpeg').content_type)
    assert_equal('application/json', new_asset('/data.json').content_type)
    assert_equal('image/png',        new_asset('/graphic.png').content_type)
    assert_equal('image/svg+xml',    new_asset('/graphic.svg').content_type)
    assert_equal('text/plain',       new_asset('/robots.txt').content_type)
    assert_equal('font/woff',        new_asset('/font.woff').content_type)
    assert_equal('font/woff2',       new_asset('/font.woff2').content_type)
  end

  ##########################################################################################################
  ## Test #binary?                                                                                        ##
  ##########################################################################################################

  test('#binary? returns false if asset is not binary') do
    refute(new_asset('/app.css').binary?)
    refute(new_asset('/index.htm').binary?)
    refute(new_asset('/index.html').binary?)
    refute(new_asset('/template.htx').binary?)
    refute(new_asset('/app.js').binary?)
    refute(new_asset('/data.json').binary?)
    refute(new_asset('/graphic.svg').binary?)
    refute(new_asset('/robots.txt').binary?)
  end

  test('#binary? returns true if asset is binary') do
    assert(new_asset('/favicon.ico').binary?)
    assert(new_asset('/photo.jpg').binary?)
    assert(new_asset('/photo.jpeg').binary?)
    assert(new_asset('/graphic.png').binary?)
    assert(new_asset('/font.woff').binary?)
    assert(new_asset('/font.woff2').binary?)
  end

  ##########################################################################################################
  ## Test #font?                                                                                          ##
  ##########################################################################################################

  test('#font? returns false if asset is not a font') do
    refute(new_asset('/app.css').font?)
    refute(new_asset('/index.htm').font?)
    refute(new_asset('/index.html').font?)
    refute(new_asset('/template.htx').font?)
    refute(new_asset('/favicon.ico').font?)
    refute(new_asset('/app.js').font?)
    refute(new_asset('/photo.jpg').font?)
    refute(new_asset('/photo.jpeg').font?)
    refute(new_asset('/data.json').font?)
    refute(new_asset('/graphic.png').font?)
    refute(new_asset('/graphic.svg').font?)
    refute(new_asset('/robots.txt').font?)
  end

  test('#font? returns true if asset is a font') do
    assert(new_asset('/font.woff').font?)
    assert(new_asset('/font.woff2').font?)
  end

  ##########################################################################################################
  ## Test #image?                                                                                         ##
  ##########################################################################################################

  test('#image? returns false if asset is not an image') do
    refute(new_asset('/app.css').image?)
    refute(new_asset('/index.htm').image?)
    refute(new_asset('/index.html').image?)
    refute(new_asset('/template.htx').image?)
    refute(new_asset('/app.js').image?)
    refute(new_asset('/data.json').image?)
    refute(new_asset('/robots.txt').image?)
    refute(new_asset('/font.woff').image?)
    refute(new_asset('/font.woff2').image?)
  end

  test('#image? returns true if asset is an image') do
    assert(new_asset('/favicon.ico').image?)
    assert(new_asset('/photo.jpg').image?)
    assert(new_asset('/photo.jpeg').image?)
    assert(new_asset('/graphic.png').image?)
    assert(new_asset('/graphic.svg').image?)
  end

  ##########################################################################################################
  ## Test #headers                                                                                        ##
  ##########################################################################################################

  test('#headers includes Content-Type header') do
    assert_equal('text/css',         new_asset('/app.css').headers['Content-Type'])
    assert_equal('text/html',        new_asset('/index.htm').headers['Content-Type'])
    assert_equal('text/html',        new_asset('/index.html').headers['Content-Type'])
    assert_equal('text/javascript',  new_asset('/template.htx').headers['Content-Type'])
    assert_equal('image/x-icon',     new_asset('/favicon.ico').headers['Content-Type'])
    assert_equal('text/javascript',  new_asset('/app.js').headers['Content-Type'])
    assert_equal('image/jpeg',       new_asset('/photo.jpg').headers['Content-Type'])
    assert_equal('image/jpeg',       new_asset('/photo.jpeg').headers['Content-Type'])
    assert_equal('application/json', new_asset('/data.json').headers['Content-Type'])
    assert_equal('image/png',        new_asset('/graphic.png').headers['Content-Type'])
    assert_equal('image/svg+xml',    new_asset('/graphic.svg').headers['Content-Type'])
    assert_equal('text/plain',       new_asset('/robots.txt').headers['Content-Type'])
    assert_equal('font/woff',        new_asset('/font.woff').headers['Content-Type'])
    assert_equal('font/woff2',       new_asset('/font.woff2').headers['Content-Type'])
  end

  test('#headers includes Cache-Control header if :versioned is not specified') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    headers = asset.headers

    assert_equal('public, max-age=31536000', headers['Cache-Control'])
    assert_nil(headers['ETag'])
  end

  test('#headers includes Cache-Control header if :versioned is true') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    headers = asset.headers(versioned: true)

    assert_equal('public, max-age=31536000', headers['Cache-Control'])
    assert_nil(headers['ETag'])
  end

  test('#headers includes ETag header if :versioned is false') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    headers = asset.headers(versioned: false)

    assert_equal('"ef0f76b822009ab847bd6a370e911556"', headers['ETag'])
    assert_nil(headers['Cache-Control'])
  end

  ##########################################################################################################
  ## Test #integrity                                                                                      ##
  ##########################################################################################################

  test('#integrity returns subresource integrity string according to algorithm argument') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    assert_equal('sha256-S9v8mQ0Xba2sG+AEXC4IpdFUM2EX/oRNADEeJ5MpV3s=', asset.integrity(:sha256))
    assert_equal('sha384-2nxTl5wRLPxsDXWEi27WU3OmaXL2BxWbycv+O0ICyA11sCQMbb1K/uREBxvBKaMT',
      asset.integrity(:sha384))
    assert_equal('sha512-VAhb8yjzGIyuPN8kosvMhu7ix55T8eLHdOqrYNcXwA6rPUlt1/420xdSzl2SNHOp93piKyjcNkQwh2Lw8'\
      'imrQA==', asset.integrity(:sha512))
  end

  test('#integrity returns sha384 subresource integrity string by default') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    assert_equal('sha384-2nxTl5wRLPxsDXWEi27WU3OmaXL2BxWbycv+O0ICyA11sCQMbb1K/uREBxvBKaMT', asset.integrity)
  end

  test('#integrity raises error if algorithm argument is not recognized') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    error = assert_raises(RuntimeError) do
      asset.integrity(:sha)
    end

    assert_equal('Unrecognized integrity algorithm: sha', error.to_s)
  end

  ##########################################################################################################
  ## Test #internal?                                                                                      ##
  ##########################################################################################################

  test('#internal? returns true if asset was initialized as internal') do
    asset = new_asset('/app.js', "console.log('Hello')", internal: true)
    asset.process

    assert(asset.internal?)
  end

  test('#internal? returns false if asset was initialized as non-internal') do
    asset = new_asset('/app.js', "console.log('Hello')", internal: false)
    asset.process

    refute(asset.internal?)
  end

  test('#internal? returns false if asset was initialized without specifying internal status') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    refute(asset.internal?)
  end

  ##########################################################################################################
  ## Test #error?                                                                                         ##
  ##########################################################################################################

  test('#error? returns false if there were no errors during processing') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    refute(asset.error?)
  end

  test('#error? returns true if there were one or more errors during processing') do
    asset = new_asset('/bad-import.js', "import '/does-not-exist.js'")
    asset.process

    assert(asset.error?)
  end

  ##########################################################################################################
  ## Test #inspect                                                                                        ##
  ##########################################################################################################

  test('#inspect returns a high-level object info string') do
    path = '/bad-import.js'
    content = <<~EOS
      import '/does-not-exist.js'

      console.log('Hello')
    EOS

    asset = new_asset(path, content, prefix: '/static')
    asset.process

    assert_inspect('#<Darkroom::Asset: '\
      '@errors=[#<Darkroom::AssetNotFoundError: /bad-import.js:1: Asset not found: /does-not-exist.js>], '\
      '@extension=".js", '\
      "@file=\"#{full_path(path)}\", "\
      '@fingerprint="afa0a5ffe7423f4b568f19a39b53b122", '\
      '@internal=false, '\
      '@minify=false, '\
      "@mtime=#{File.mtime(full_path(path)).inspect}, "\
      '@path="/bad-import.js", '\
      '@path_unversioned="/static/bad-import.js", '\
      '@path_versioned="/static/bad-import-afa0a5ffe7423f4b568f19a39b53b122.js", '\
      '@prefix="/static"'\
    '>', asset)
  end

  ##########################################################################################################
  ## Test Specs                                                                                           ##
  ##########################################################################################################

  test('JavaScript spec dependency regex matches import statements with proper syntax') do
    regex = Darkroom::Asset.spec('.js').dependency_regex

    assert_match(regex, %q(import ''))
    assert_match(regex, %q(import ""))
    assert_match(regex, %q(import '/single-quotes.js'))
    assert_match(regex, %q(import "/double-quotes.js"))
    assert_match(regex, %q(import '/single-quotes-semicolon.js';))
    assert_match(regex, %q(import "/double-quotes-semicolon.js";))
    assert_match(regex, %q( import  '/whitespace.js' ; ))
  end

  test('JavaScript spec dependency regex does not match import statements with bad quoting') do
    regex = Darkroom::Asset.spec('.js').dependency_regex

    # Bad quoting
    refute_match(regex, %q(import /no-quotes.js))
    refute_match(regex, %q(import "/mismatched-quotes.js'))
    refute_match(regex, %q(import '/mismatched-quotes.js"))
    refute_match(regex, %q(import /missing-open-single-quote.js'))
    refute_match(regex, %q(import /missing-open-double-quote.js"))
    refute_match(regex, %q(import '/missing-close-single-quote.js))
    refute_match(regex, %q(import "/missing-close-double-quote.js))

    # Escaped and unescaped quotes
    refute_match(regex, %q(import '/unescaped'-single-quote.js'))
    refute_match(regex, %q(import "/unescaped"-double-quote.js"))
    refute_match(regex, %q(import '/unescaped\\\\'-single-quote.js'))
    refute_match(regex, %q(import "/unescaped\\\\"-double-quote.js"))
    refute_match(regex, %q(import '/escaped\\'-single-quote.js'))
    refute_match(regex, %q(import '/escaped\\\\\\'-single-quote.js'))
    refute_match(regex, %q(import "/escaped\\"-double-quote.js"))
    refute_match(regex, %q(import "/escaped\\\\\\"-double-quote.js"))
  end

  test('CSS spec dependency regex matches import statements with proper syntax') do
    regex = Darkroom::Asset.spec('.css').dependency_regex

    assert_match(regex, %q(@import '';))
    assert_match(regex, %q(@import "";))
    assert_match(regex, %q(@import '/single-quotes.css';))
    assert_match(regex, %q(@import "/double-quotes.css";))
    assert_match(regex, %q( @import  '/whitespace.js' ; ))
  end

  test('CSS spec dependency regex does not match import statements with bad quoting') do
    regex = Darkroom::Asset.spec('.css').dependency_regex

    # Bad quoting
    refute_match(regex, %q(@import /no-quotes.css;))
    refute_match(regex, %q(@import "/mismatched-quotes.css';))
    refute_match(regex, %q(@import '/mismatched-quotes.css";))
    refute_match(regex, %q(@import /missing-open-single-quote.css';))
    refute_match(regex, %q(@import /missing-open-double-quote.css";))
    refute_match(regex, %q(@import '/missing-close-single-quote.css;))
    refute_match(regex, %q(@import "/missing-close-double-quote.css;))

    # Escaped and unescaped quotes
    refute_match(regex, %q(@import '/unescaped'-single-quote.css';))
    refute_match(regex, %q(@import "/unescaped"-double-quote.css";))
    refute_match(regex, %q(@import '/unescaped\\\\'-single-quote.css';))
    refute_match(regex, %q(@import "/unescaped\\\\"-double-quote.css";))
    refute_match(regex, %q(@import '/escaped\\'-single-quote.css';))
    refute_match(regex, %q(@import '/escaped\\\\\\'-single-quote.css';))
    refute_match(regex, %q(@import "/escaped\\"-double-quote.css";))
    refute_match(regex, %q(@import "/escaped\\\\\\"-double-quote.css";))

    # Semicolon
    refute_match(regex, %q(@import '/no-semicolon.css'))
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  class DarkroomMock
    def initialize() @manifest = {} end
    def manifest(path) @manifest[path] end
    def process_key() 1 end
  end

  def new_asset(path, content = nil, **options)
    asset = Darkroom::Asset.new(path, full_path(path), @@darkroom, **options)

    write_files(path => content) if content
    @@darkroom.instance_variable_get(:@manifest)[asset.path] = asset

    asset
  end
end
