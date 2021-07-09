# frozen_string_literal: true

require('darkroom/asset')
require('darkroom/darkroom')
require('darkroom/version')

require('darkroom/errors/asset_not_found_error')
require('darkroom/errors/duplicate_asset_error')
require('darkroom/errors/invalid_path_error')
require('darkroom/errors/missing_library_error')
require('darkroom/errors/processing_error')
require('darkroom/errors/spec_not_defined_error')

class Darkroom
  QUOTED_PATH = '(?<quote>[\'"])(?<path>[^\'"]*)\k<quote>'

  Asset.add_spec('.css', 'text/css',
    dependency_regex: /^ *@import +#{QUOTED_PATH} *; *$/,
    minify: -> (content) { SassC::Engine.new(content, style: :compressed).render },
    minify_lib: 'sassc',
  )

  Asset.add_spec('.js', 'application/javascript',
    dependency_regex: /^ *import +#{QUOTED_PATH} *;? *$/,
    minify: -> (content) { Uglifier.compile(content, harmony: true) },
    minify_lib: 'uglifier',
  )

  Asset.add_spec('.htx', 'application/javascript',
    compile: -> (path, content) { HTX.compile(path, content) },
    compile_lib: 'htx',
    minify: Asset.spec('.js').minify,
    minify_lib: Asset.spec('.js').minify_lib,
  )

  Asset.add_spec('.htm', '.html', 'text/html')
  Asset.add_spec('.ico', 'image/x-icon')
  Asset.add_spec('.jpg', '.jpeg', 'image/jpeg')
  Asset.add_spec('.json', 'application/json')
  Asset.add_spec('.png', 'image/png')
  Asset.add_spec('.svg', 'image/svg+xml')
  Asset.add_spec('.txt', 'text/plain')
  Asset.add_spec('.woff', 'font/woff')
  Asset.add_spec('.woff2', 'font/woff2')
end
