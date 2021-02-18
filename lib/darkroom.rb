# frozen_string_literal: true

require('darkroom/asset')
require('darkroom/darkroom')
require('darkroom/version')

require('darkroom/errors/asset_not_found_error')
require('darkroom/errors/duplicate_asset_error')
require('darkroom/errors/missing_library_error')
require('darkroom/errors/processing_error')
require('darkroom/errors/spec_not_defined_error')

Darkroom::Asset.add_spec('.css', 'text/css',
  dependency_regex: /^ *@import +(?<quote>['"]) *(?<path>.*) *\g<quote> *; *$/,
  minify: -> (content) { CSSminify.compress(content) },
  minify_lib: 'cssminify',
)

Darkroom::Asset.add_spec('.js', 'application/javascript',
  dependency_regex: /^ *import +(?<quote>['"])(?<path>.*)\g<quote> *;? *$/,
  minify: -> (content) { Uglifier.compile(content, harmony: true) },
  minify_lib: 'uglifier',
)

Darkroom::Asset.add_spec('.htx', 'application/javascript',
  compile: -> (path, content) { HTX.compile(path, content) },
  compile_lib: 'htx',
  minify: Darkroom::Asset.spec('.js').minify,
  minify_lib: Darkroom::Asset.spec('.js').minify_lib,
)

Darkroom::Asset.add_spec('.html', '.html', 'text/html')
Darkroom::Asset.add_spec('.ico', 'image/x-icon')
Darkroom::Asset.add_spec('.jpg', '.jpeg', 'image/jpeg')
Darkroom::Asset.add_spec('.png', 'image/png')
Darkroom::Asset.add_spec('.svg', 'image/svg+xml')
Darkroom::Asset.add_spec('.txt', 'text/plain')
Darkroom::Asset.add_spec('.woff', 'font/woff')
Darkroom::Asset.add_spec('.woff2', 'font/woff2')
