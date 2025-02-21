# frozen_string_literal: true

require_relative('test_helper')

class AssetTest < Minitest::Test
  include(TestHelper)

  IIFE_PREFIX = <<~JS
    ((...bundle) => {
      const modules = {}
      const setters = []
      const $import = (name, setter) =>
        modules[name] ? setter(modules[name]) : setters.push([setter, name])

      for (const [name, def] of bundle)
        modules[name] = def($import)

      for (const [setter, name] of setters)
        setter(modules[name])
    })(
  JS

  ##########################################################################################################
  ## Constructor                                                                                          ##
  ##########################################################################################################

  test('raises UnrecognizedExtensionError if file extension is not registered') do
    error = assert_raises(Darkroom::UnrecognizedExtensionError) do
      new_asset('/app.undefined')
    end

    assert_equal('File extension not recognized: /app.undefined', error.to_s)
  end

  test('requires compile library if delegate specifies one') do
    Darkroom.register('.dummy-compile', 'text/dummy-compile') do
      compile(lib: 'dummy_compile')
    end

    refute(defined?(DummyCompile), 'Expected DummyCompile to be undefined before asset is initialized.')

    new_asset('/app.dummy-compile')

    assert(defined?(DummyCompile), 'Expected DummyCompile to be defined after asset is initialized.')
  ensure
    Darkroom.register('.dummy-compile', nil)
  end

  test('requires finalize library if delegate specifies one') do
    Darkroom.register('.dummy-finalize', 'text/dummy-finalize') do
      finalize(lib: 'dummy_finalize')
    end

    refute(defined?(DummyFinalize), 'Expected DummyFinalize to be undefined before asset is initialized.')

    new_asset('/app.dummy-finalize')

    assert(defined?(DummyFinalize), 'Expected DummyFinalize to be defined after asset is initialized.')
  ensure
    Darkroom.register('.dummy-finalize', nil)
  end

  test('requires minify library if delegate specifies one and minification is enabled') do
    Darkroom.register('.dummy-minify', 'text/dummy-minify') do
      minify(lib: 'dummy_minify')
    end

    new_asset('/app.dummy-minify')

    refute(defined?(DummyMinify), 'Expected DummyMinify to be undefined when minification is not enabled.')

    new_asset('/app.dummy-minify', minify: true)

    assert(defined?(DummyMinify), 'Expected DummyMinify to be defined when minification is enabled.')
  ensure
    Darkroom.register('.dummy-minify', nil)
  end

  test('raises MissingLibraryError if compile library is not available') do
    Darkroom.register('.bad-compile', 'text/bad-compile') do
      compile(lib: 'bad_compile')
    end

    error = assert_raises(Darkroom::MissingLibraryError) do
      new_asset('/app.bad-compile')
    end

    assert_equal('Cannot compile .bad-compile files: \'bad_compile\' library not available [hint: try ' \
      'adding gem(\'bad_compile\') to your Gemfile]', error.to_s)
  ensure
    Darkroom.register('.bad-compile', nil)
  end

  test('raises MissingLibraryError if finalize library is not available') do
    Darkroom.register('.bad-finalize', 'text/bad-finalize') do
      finalize(lib: 'bad_finalize')
    end

    error = assert_raises(Darkroom::MissingLibraryError) do
      new_asset('/app.bad-finalize')
    end

    assert_equal('Cannot finalize .bad-finalize files: \'bad_finalize\' library not available [hint: try ' \
      'adding gem(\'bad_finalize\') to your Gemfile]', error.to_s)
  ensure
    Darkroom.register('.bad-finalize', nil)
  end

  test('raises MissingLibraryError if minification is enabled and minify library is missing') do
    Darkroom.register('.bad-minify', 'text/bad-minify') do
      minify(lib: 'bad_minify')
    end

    begin
      new_asset('/app.bad-minify')
    rescue Darkroom::MissingLibraryError
      assert(false, 'Expected minify library to not be required when minification is not enabled')
    end

    error = assert_raises(Darkroom::MissingLibraryError) do
      new_asset('/app.bad-minify', minify: true)
    end

    assert_equal('Cannot minify .bad-minify files: \'bad_minify\' library not available [hint: try ' \
      'adding gem(\'bad_minify\') to your Gemfile]', error.to_s)
  ensure
    Darkroom.register('.bad-minify', nil)
  end

  ##########################################################################################################
  ## Processing                                                                                           ##
  ##########################################################################################################

  test('compiles content if implemented in delegate') do
    Darkroom.register('.compile') do
      compile do |parse_data:, path:, own_content:|
        '[compiled]'
      end
    end

    asset = new_asset('/template.compile', 'not compiled')
    asset.process

    refute_error(asset.errors)
    assert_equal('[compiled]', asset.content)
  ensure
    Darkroom.register('.compile', nil)
  end

  test('processes using compiled delegate if one is implemented') do
    asset = new_asset('/template.htx', '<div>${this.hello}</div>')
    new_asset('/import.js', '[import]')

    HTX.stub(:compile, ->(*) { "import '/import.js'\n\n[compiled]" }) do
      asset.process
    end

    refute_error(asset.errors)
    assert_equal("[import]\n\n[compiled]", asset.content)
  end

  test('finalizes content if implemented in delegate') do
    Darkroom.register('.finalize') do
      finalize do |parse_data:, path:, content:|
        '[finalized]'
      end
    end

    asset = new_asset('/template.finalize', 'not finalized')
    asset.process

    refute_error(asset.errors)
    assert_equal('[finalized]', asset.content)
  ensure
    Darkroom.register('.finalize', nil)
  end

  test('minifies content if implemented in delegate and minification is enabled') do
    Darkroom.register('.minify') do
      minify do |parse_data:, path:, content:|
        '[minified]'
      end
    end

    asset1 = new_asset('/template.minify', 'not minified')
    asset2 = new_asset('/template.minify', 'not minified', minify: true)

    asset1.process
    asset2.process

    refute_error(asset1.errors)
    refute_error(asset2.errors)

    assert_equal('not minified', asset1.content)
    assert_equal('[minified]', asset2.content)
  ensure
    Darkroom.register('.minify', nil)
  end

  test('merges imported content with own content when referenced by absolute path') do
    new_asset('/import.js', "console.log('Import')")
    asset = new_asset('/app.js', "import '/import.js'\n\nconsole.log('App')")

    asset.process

    refute_error(asset.errors)
    assert_equal("console.log('Import')\n\nconsole.log('App')", asset.content)
  end

  test('merges imported content with own content when referenced by relative path') do
    new_asset('/import1.js', "console.log('Import1')")
    new_asset('/components/import2.js', "console.log('Import2')")
    asset = new_asset('/components/component.js', "import '../import1.js'\nimport 'import2.js'\n\n" \
      "console.log('App')")

    asset.process

    refute_error(asset.errors)
    assert_equal("console.log('Import1')\nconsole.log('Import2')\n\nconsole.log('App')", asset.content)
  end

  test('registers error when reference does not exist') do
    content = <<~HTML
      <body>
        <img src='/logo.svg?asset-path'>
        <img src='/graphic.svg?asset-content'>
      </body>
    HTML

    asset = new_asset('/index.html', content)
    asset.process

    assert_error(
      '#<Darkroom::AssetNotFoundError: /index.html:2: Asset not found: /logo.svg>',
      '#<Darkroom::AssetNotFoundError: /index.html:3: Asset not found: /graphic.svg>',
      asset.errors
    )
  end

  test('registers error when reference entity is invalid') do
    Darkroom.register('.ext', Darkroom::HTMLDelegate) do
      reference(/
        <img\ src=(?<quote>')(?<quoted>
          (?<path>.*)\?asset-(?<entity>bad)(?:=(?<format>.*))?
        )\k<quote>>
      /x)
    end

    new_asset('/logo.svg', '<svg></svg>')
    asset = new_asset('/index.ext', "<img src='/logo.svg?asset-bad'>")
    asset.process

    assert_error(
      "#<Darkroom::AssetError: /index.ext:1: Invalid reference entity 'bad' (must be one of 'path', " \
        "'content'): <img src='/logo.svg?asset-bad'>>",
      asset.errors
    )
  end

  test('registers error when reference format is invalid') do
    new_asset('/logo.svg', '<svg></svg>')
    new_asset('/graphic.svg', '<svg></svg>')

    content = <<~HTML
      <body>
        <img src='/logo.svg?asset-path=invalid'>
        <img src='/graphic.svg?asset-content=invalid'>
      </body>
    HTML

    asset = new_asset('/index.html', content)
    asset.process

    assert_error(
      "#<Darkroom::AssetError: /index.html:2: Invalid reference format 'invalid' (must be one of " \
        "'versioned', 'unversioned'): <img src='/logo.svg?asset-path=invalid'>>",
      "#<Darkroom::AssetError: /index.html:3: Invalid reference format 'invalid' (must be one of " \
        "'base64', 'utf8', 'displace'): <img src='/graphic.svg?asset-content=invalid'>>",
      asset.errors
    )
  end

  test('registers error when reference is binary and format is not base64') do
    new_asset('/logo.png')
    new_asset('/graphic.png')

    content = <<~HTML
      <body>
        <img src='/logo.png?asset-content=utf8'>
        <img src='/graphic.png?asset-content=displace'>
      </body>
    HTML

    asset = new_asset('/index.html', content)
    asset.process

    assert_error(
      '#<Darkroom::AssetError: /index.html:2: Base64 encoding is required for binary assets: <img ' \
        "src='/logo.png?asset-content=utf8'>>",
      '#<Darkroom::AssetError: /index.html:3: Base64 encoding is required for binary assets: <img ' \
        "src='/graphic.png?asset-content=displace'>>",
      asset.errors
    )
  end

  test('registers error when reference delegate validation fails') do
    new_asset('/robots.txt')

    asset = new_asset('/app.css', 'body { background: url(/robots.txt?asset-path); }')
    asset.process

    assert_error(
      '#<Darkroom::AssetError: /app.css:1: Referenced asset must be an image or font type: ' \
        'url(/robots.txt?asset-path)>',
      asset.errors
    )
  end

  test('registers error when reference would result in a circular reference chain') do
    circular1 = new_asset('/circular1.html', "<body><a href='/circular2.html?asset-path'></a></body>")
    new_asset('/circular2.html', "<body><a href='/circular3.html?asset-path'></a></body>")
    new_asset('/circular3.html', "<body><a href='/circular1.html?asset-path'></a></body>")

    circular1.process

    assert_error(
      '#<Darkroom::CircularReferenceError: /circular1.html:1: Reference would result in a circular ' \
        "reference chain: <a href='/circular2.html?asset-path'>>",
      circular1.errors
    )
  end

  test('registers errors of intermediate asset') do
    content = <<~HTML
      <body>
        <img src='/logo.svg?asset-path'>
        <img src='/graphic.svg?asset-content'>
      </body>
    HTML

    asset = new_asset('/index.htx', content)

    HTX.stub(:compile, ->(*) { '[compiled]' }) do
      asset.process
    end

    assert_error(
      '#<Darkroom::AssetNotFoundError: /index.htx:2: Asset not found: /logo.svg>',
      '#<Darkroom::AssetNotFoundError: /index.htx:3: Asset not found: /graphic.svg>',
      asset.errors
    )
  end

  test('substitutes versioned path of reference when path format is unspecified') do
    new_asset('/logo.svg', '<svg></svg>')
    asset = new_asset('/index.html', "<body><img src='/logo.svg?asset-path'></body>")

    asset.process

    refute_error(asset.errors)
    assert_equal("<body><img src='/logo-7b56e1eab00ec8000da9331a4888cb35.svg'></body>", asset.content)
  end

  test('substitutes versioned path of reference when path format is versioned') do
    new_asset('/logo.svg', '<svg></svg>')
    asset = new_asset('/index.html', "<body><img src='/logo.svg?asset-path=versioned'></body>")

    asset.process

    refute_error(asset.errors)
    assert_equal("<body><img src='/logo-7b56e1eab00ec8000da9331a4888cb35.svg'></body>", asset.content)
  end

  test('substitutes unversioned path of reference when path format is unversioned') do
    new_asset('/logo.svg', '<svg></svg>')
    asset = new_asset('/index.html', "<body><img src='/logo.svg?asset-path=unversioned'></body>")

    asset.process

    refute_error(asset.errors)
    assert_equal("<body><img src='/logo.svg'></body>", asset.content)
  end

  test('substitutes base64-encoded content of reference when content format is unspecified') do
    new_asset('/logo.svg', '<svg></svg>')
    asset = new_asset('/index.html', "<body><img src='/logo.svg?asset-content'></body>")

    asset.process

    refute_error(asset.errors)
    assert_equal("<body><img src='data:image/svg+xml;base64,PHN2Zz48L3N2Zz4='></body>", asset.content)
  end

  test('substitutes base64-encoded content of reference when content format is base64') do
    new_asset('/logo.svg', '<svg></svg>')
    asset = new_asset('/index.html', "<body><img src='/logo.svg?asset-content=base64'></body>")

    asset.process

    refute_error(asset.errors)
    assert_equal("<body><img src='data:image/svg+xml;base64,PHN2Zz48L3N2Zz4='></body>", asset.content)
  end

  test('substitutes utf8-encoded content of reference when content format is utf8') do
    new_asset('/logo.svg', '<svg></svg>')
    asset = new_asset('/index.html', "<body><img src='/logo.svg?asset-content=utf8'></body>")

    asset.process

    refute_error(asset.errors)
    assert_equal("<body><img src='data:image/svg+xml;utf8,<svg></svg>'></body>", asset.content)
  end

  test('displaces content with reference content when content format is displace') do
    new_asset('/logo.svg', '<svg></svg>')
    asset = new_asset('/index.html', "<body><img src='/logo.svg?asset-content=displace'></body>")

    asset.process

    refute_error(asset.errors)
    assert_equal('<body><svg></svg></body>', asset.content)
  end

  test('gracefully handles asset file being deleted on disk') do
    asset = new_asset('/deleted.js')
    asset.process

    refute_error(asset.errors)
    assert_empty(asset.content)
  end

  test('does not register any errors if successful') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    refute_error(asset.errors)
  end

  test('registers an error when an import is not found') do
    content = <<~JS
      import '/does-not-exist.js'

      console.log('Hello')
    JS

    asset = new_asset('/bad-import.js', content)
    asset.process

    assert_error(
      '#<Darkroom::AssetNotFoundError: /bad-import.js:1: Asset not found: /does-not-exist.js>',
      asset.errors
    )
  end

  test('registers an error when compilation raises an exception') do
    asset = new_asset('/template.htx', '<div>${this.hello}</div>')

    HTX.stub(:compile, ->(*) { raise('[HTX Error]') }) do
      asset.process
    end

    assert_error('#<RuntimeError: [HTX Error]>', asset.errors)
  end

  test('registers an error when finalization raises an exception') do
    Darkroom.register('.dummy-finalize', 'text/dummy-finalize') do
      finalize do |parse_data:, path:, content:|
        raise('[Finalize Error]')
      end
    end

    asset = new_asset('/template.dummy-finalize', '<div>${this.hello}</div>')
    asset.process

    assert_error('#<RuntimeError: [Finalize Error]>', asset.errors)
  end

  test('registers an error when minification raises an exception') do
    asset = new_asset('/app.js', "console.log('Hello')", minify: true)

    Terser.stub(:compile, ->(*) { raise('[Terser Error]') }) do
      asset.process
    end

    assert_error('#<RuntimeError: [Terser Error]>', asset.errors)
  end

  test('accumulates multiple errors') do
    content = <<~JS
      import '/does-not-exist.js'
      import '/also-does-not-exist.js'

      console.log('Hello')
    JS

    asset = new_asset('/bad-imports.js', content, minify: true)

    Terser.stub(:compile, ->(*) { raise('[Terser Error]') }) do
      asset.process
    end

    assert_error(
      '#<Darkroom::AssetNotFoundError: /bad-imports.js:1: Asset not found: /does-not-exist.js>',
      '#<Darkroom::AssetNotFoundError: /bad-imports.js:2: Asset not found: /also-does-not-exist.js>',
      '#<RuntimeError: [Terser Error]>',
      asset.errors
    )
  end

  test('handles circular imports') do
    asset1 = new_asset('/circular1.css', "@import '/circular2.css';\n\n.circular1 {}")
    asset2 = new_asset('/circular2.css', "@import '/circular3.css';\n\n.circular2 {}")
    asset3 = new_asset('/circular3.css', "@import '/circular1.css';\n\n.circular3 {}")

    asset1.process

    refute_error(asset1.errors)
    refute_error(asset2.errors)
    refute_error(asset3.errors)

    assert_equal("\n.circular3 {}\n\n.circular2 {}\n\n.circular1 {}", asset1.content)
    assert_equal("\n.circular1 {}\n\n.circular3 {}\n\n.circular2 {}", asset2.content)
    assert_equal("\n.circular2 {}\n\n.circular1 {}\n\n.circular3 {}", asset3.content)
  end

  test('compiles circular imports before including their contents') do
    Darkroom.register('.simple-compile', 'text/simple-compile') do
      import(/^import (?<quote>')(?<path>.+)\k<quote>$/)
      compile { |parse_data:, path:, own_content:| own_content.upcase }
    end

    asset1 = new_asset('/circular1.simple-compile', "import '/circular2.simple-compile'\ncircular1")
    asset2 = new_asset('/circular2.simple-compile', "import '/circular1.simple-compile'\ncircular2")

    asset1.process

    assert_equal("\nCIRCULAR2\n\nCIRCULAR1", asset1.content)
    assert_equal("\nCIRCULAR1\n\nCIRCULAR2", asset2.content)
  ensure
    Darkroom.register('.simple-compile', nil)
  end

  test('determines dependencies by walking dependency chain with self as root') do
    asset1 = new_asset('/circular1.css', "@import '/circular2.css';\n\n.circular1 {}")
    asset2 = new_asset('/circular2.css', "@import '/circular3.css';\n\n.circular2 {}")
    asset3 = new_asset('/circular3.css', "@import '/circular2.css';\n\n.circular3 {}")

    asset1.process
    asset1.send(:dependencies)

    assert_includes(asset3.send(:dependencies).map(&:path), asset2.path)
  end

  ##########################################################################################################
  ## Processing - JavaScript                                                                              ##
  ##########################################################################################################

  test('concatenates JavaScript side-effect imports when IIFE are not enabled') do
    new_asset('/import.js', "console.log('Import')\n")
    asset = new_asset('/app.js', "import '/import.js'\n\nconsole.log('App')\n")
    processed = <<~JS
      console.log('Import')

      console.log('App')
    JS

    asset.process

    refute_error(asset.errors)
    assert_equal(processed, asset.content)
  end

  test('concatenates JavaScript named imports when IIFE are not enabled') do
    new_asset('/import.js', "export function Import() { console.log('Import') }\n")
    asset = new_asset('/app.js', "import {Import} from '/import.js'\n\nconsole.log('App')\n")
    processed = <<~JS
      function Import() { console.log('Import') }

      console.log('App')
    JS

    asset.process

    refute_error(asset.errors)
    assert_equal(processed, asset.content)
  end

  test('generates IIFE for JavaScript assets with no imports when IIFE are enabled') do
    Darkroom.javascript_iife = true

    asset = new_asset('/app.js', "console.log('App')\n")
    processed = <<~JS
      #{IIFE_PREFIX}
      ['/app.js', $import => {

      console.log('App')

      return Object.seal({})

      }],

      )
    JS

    asset.process

    refute_error(asset.errors)
    assert_equal(processed, asset.content)
  ensure
    Darkroom.javascript_iife = false
  end

  test('generates IIFE for JavaScript assets with side-effect imports when IIFE are enabled') do
    Darkroom.javascript_iife = true

    new_asset('/import.js', "console.log('Import')\n")
    asset = new_asset('/app.js', "import '/import.js'\n\nconsole.log('App')\n")
    processed = <<~JS
      #{IIFE_PREFIX}
      ['/import.js', $import => {

      console.log('Import')

      return Object.seal({})

      }],

      ['/app.js', $import => {


      console.log('App')

      return Object.seal({})

      }],

      )
    JS

    asset.process

    refute_error(asset.errors)
    assert_equal(processed, asset.content)
  ensure
    Darkroom.javascript_iife = false
  end

  test('generates IIFE for JavaScript assets with named imports when IIFE are enabled') do
    Darkroom.javascript_iife = true

    new_asset('/default.js', "export default function Default() { console.log('Default') }\n")
    new_asset('/named.js', "export function Named() { console.log('Named') }\n")
    new_asset('/aliased.js', "function Aliased() { console.log('Aliased') }\nexport {Aliased as " \
      "'Something Else', Aliased as 'Another'}\n")

    asset = new_asset(
      '/app.js',
      <<~JS
        import Default from '/default.js'
        import {Import} from '/named.js'
        import {Aliased as Renamed} from '/aliased.js'

        console.log('App')
      JS
    )

    processed = <<~JS
      #{IIFE_PREFIX}
      ['/default.js', $import => {

      function Default() { console.log('Default') }

      return Object.seal({
        default: Default,
      })

      }],

      ['/named.js', $import => {

      function Named() { console.log('Named') }

      return Object.seal({
        Named: Named,
      })

      }],

      ['/aliased.js', $import => {

      function Aliased() { console.log('Aliased') }

      return Object.seal({
        'Something Else': Aliased,
        'Another': Aliased,
      })

      }],

      ['/app.js', $import => {

      let Default; $import('/default.js', m => Default = m.default)
      let Import; $import('/named.js', m => Import = m.Import)
      let Renamed; $import('/aliased.js', m => Renamed = m.Aliased)

      console.log('App')

      return Object.seal({})

      }],

      )
    JS

    asset.process

    refute_error(asset.errors)
    assert_equal(processed, asset.content)
  ensure
    Darkroom.javascript_iife = false
  end

  ##########################################################################################################
  ## #content_type                                                                                        ##
  ##########################################################################################################

  test('#content_type returns the HTTP MIME type string for the asset') do
    assert_equal('image/apng',       new_asset('/animation.apng').content_type)
    assert_equal('image/avif',       new_asset('/graphic.avif').content_type)
    assert_equal('text/css',         new_asset('/app.css').content_type)
    assert_equal('image/gif',        new_asset('/graphic.gif').content_type)
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
    assert_equal('image/webp',       new_asset('/graphic.webp').content_type)
    assert_equal('font/woff',        new_asset('/font.woff').content_type)
    assert_equal('font/woff2',       new_asset('/font.woff2').content_type)
  end

  ##########################################################################################################
  ## #binary?                                                                                             ##
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
  ## #font?                                                                                               ##
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

  test('#font?returns true if asset is a font') do
    assert(new_asset('/font.woff').font?)
    assert(new_asset('/font.woff2').font?)
  end

  ##########################################################################################################
  ## #image?                                                                                              ##
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
  ## #entry?                                                                                              ##
  ##########################################################################################################

  test('#entry? returns true if asset was initialized as an entry point') do
    asset = new_asset('/app.js', "console.log('Hello')", entry: true)

    assert(asset.entry?)
  end

  test('#entry? returns false if asset was initialized as not an entry point') do
    asset = new_asset('/app.js', "console.log('Hello')", entry: false)

    refute(asset.entry?)
  end

  test('#entry? returns true if asset was initialized without specifying entry status') do
    asset = new_asset('/app.js', "console.log('Hello')")

    assert(asset.entry?)
  end

  ##########################################################################################################
  ## #error?                                                                                              ##
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
  ## #error                                                                                               ##
  ##########################################################################################################

  test('#error returns nil if there were no errors during processing') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    assert_nil(asset.error)
  end

  test('#error returns ProcessingError if there were one or more errors during processing') do
    asset = new_asset('/bad-import.js', "import '/bad1.js'\nimport '/bad2.js'")
    asset.process

    assert_error(
      <<~TEXT.strip,
        #<Darkroom::ProcessingError: Errors were encountered while processing assets:
          /bad-import.js:1: Asset not found: /bad1.js
          /bad-import.js:2: Asset not found: /bad2.js>
      TEXT
      asset.error
    )

    expected_errors = [
      '#<Darkroom::AssetNotFoundError: /bad-import.js:1: Asset not found: /bad1.js>',
      '#<Darkroom::AssetNotFoundError: /bad-import.js:2: Asset not found: /bad2.js>',
    ]

    asset.error.each.with_index do |error, i|
      assert_error(expected_errors[i], error)
    end
  end

  ##########################################################################################################
  ## #fingerprint                                                                                         ##
  ##########################################################################################################

  test('#fingerprint returns MD5 hash of asset content') do
    new_asset('/import.js', "console.log('Import')")
    asset = new_asset('/app.js', "import '/import.js'\n\nconsole.log('App')")

    asset.process

    assert_equal('31bc73566fb11439130454b88fc4efa1', asset.fingerprint)
  end

  ##########################################################################################################
  ## #path_versioned                                                                                      ##
  ##########################################################################################################

  test('#path_versioned returns versioned path') do
    new_asset('/import.js', "console.log('Import')")
    asset = new_asset('/app.js', "import '/import.js'\n\nconsole.log('App')")

    asset.process

    assert_equal('/app-31bc73566fb11439130454b88fc4efa1.js', asset.path_versioned)
  end

  ##########################################################################################################
  ## #headers                                                                                             ##
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

    refute_error(asset.errors)
    assert_equal('public, max-age=31536000', headers['Cache-Control'])
    assert_nil(headers['ETag'])
  end

  test('#headers includes Cache-Control header if :versioned is true') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    headers = asset.headers(versioned: true)

    refute_error(asset.errors)
    assert_equal('public, max-age=31536000', headers['Cache-Control'])
    assert_nil(headers['ETag'])
  end

  test('#headers includes ETag header if :versioned is false') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    headers = asset.headers(versioned: false)

    refute_error(asset.errors)
    assert_equal('"ef0f76b822009ab847bd6a370e911556"', headers['ETag'])
    assert_nil(headers['Cache-Control'])
  end

  ##########################################################################################################
  ## #integrity                                                                                           ##
  ##########################################################################################################

  test('#integrity returns subresource integrity string according to algorithm argument') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    refute_error(asset.errors)

    assert_equal('sha256-S9v8mQ0Xba2sG+AEXC4IpdFUM2EX/oRNADEeJ5MpV3s=', asset.integrity(:sha256))

    assert_equal(
      'sha384-2nxTl5wRLPxsDXWEi27WU3OmaXL2BxWbycv+O0ICyA11sCQMbb1K/uREBxvBKaMT',
      asset.integrity(:sha384)
    )

    assert_equal(
      'sha512-VAhb8yjzGIyuPN8kosvMhu7ix55T8eLHdOqrYNcXwA6rPUlt1/420xdSzl2SNHOp93piKyjcNkQwh2Lw8imrQA==',
      asset.integrity(:sha512)
    )
  end

  test('#integrity returns sha384 subresource integrity string by default') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    refute_error(asset.errors)
    assert_equal(
      'sha384-2nxTl5wRLPxsDXWEi27WU3OmaXL2BxWbycv+O0ICyA11sCQMbb1K/uREBxvBKaMT',
      asset.integrity
    )
  end

  test('#integrity raises error if algorithm argument is not recognized') do
    asset = new_asset('/app.js', "console.log('Hello')")
    asset.process

    error = assert_raises(RuntimeError) do
      asset.integrity(:sha)
    end

    refute_error(asset.errors)
    assert_equal('Unrecognized integrity algorithm: sha', error.to_s)
  end

  ##########################################################################################################
  ## #inspect                                                                                             ##
  ##########################################################################################################

  test('#inspect returns a high-level object info string') do
    path = '/bad-import.js'
    content = <<~JS
      import '/does-not-exist.js'

      console.log('Hello')
    JS

    asset = new_asset(path, content, prefix: '/static')
    asset.process

    assert_inspect('#<Darkroom::Asset ' \
      '@delegate=Darkroom::JavaScriptDelegate, ' \
      '@dir="/", ' \
      '@entry=true, ' \
      '@errors=[#<Darkroom::AssetNotFoundError: /bad-import.js:1: Asset not found: /does-not-exist.js>], ' \
      '@extension=".js", ' \
      "@file=\"#{full_path(path)}\", " \
      '@fingerprint="5f3acf6b7220af7a522fab7b95e47333", ' \
      '@minify=false, ' \
      '@modified=true, ' \
      "@mtime=#{File.mtime(full_path(path)).inspect}, " \
      '@path="/bad-import.js", ' \
      '@path_unversioned="/static/bad-import.js", ' \
      '@path_versioned="/static/bad-import-5f3acf6b7220af7a522fab7b95e47333.js", ' \
      '@prefix="/static"' \
    '>', asset)
  end
end
