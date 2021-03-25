# Darkroom

Darkroom is a fast, lightweight, and straightforward web asset management library. Processed assets are all
stored in and served directly from memory rather than being written to disk (though a dump to disk can be
performed for upload to a CDN or proxy server in production environments); this keeps asset management
simple and performant in development. Darkroom also supports asset bundling for CSS and JavaScript using
each language's native import statement syntax.

The following file types are supported out of the box, though support for others can be added (see the
[Extending](#extending) section):

| Name       | Content Type           | Exension(s) |
| ---------- |----------------------- |-------------|
| CSS        | text/css               | .css        |
| JavaScript | application/javascript | .js         |
| HTML       | text/html              | .htm, .html |
| HTX        | application/javascript | .htx        |
| ICO        | image/x-icon           | .ico        |
| JPEG       | image/jpeg             | .jpg, .jpeg |
| PNG        | image/png              | .png        |
| SVG        | image/svg+xml          | .svg        |
| Text       | text/plain             | .txt        |
| WOFF       | font/woff              | .woff       |
| WOFF2      | font/woff2             | .woff2      |

## Installation

Add this line to your Gemfile:

```ruby
gem('darkroom')
```

Or install manually on the command line:

```bash
gem install darkroom
```

## Usage

To create and start using a Darkroom instance, specify one or more load paths (all other arguments are
optional):

```ruby
darkroom = Darkroom.new('app/assets', 'vendor/assets', '...',
  hosts: ['https://cdn1.com', '...']   # Hosts to prepend to asset paths (useful in production)
  prefix: '/static',                   # Prefix to add to all asset paths
  pristine: ['/google-verify.html'],   # Paths with no prefix or versioning (e.g. /favicon.ico)
  minify: true,                        # Minify assets that can be minified
  minified_pattern: /(\.|-)min\.\w+$/, # Files that should not be minified
  internal_pattern: /^\/components\//, # Files that cannot be accessed directly
  min_process_interval: 1,             # Minimum time that must elapse between process calls
)

# Refresh any assets that have been modified (in development, this should be called at the
# beginning of each web request).
darkroom.process

# Dump assets to disk. Useful when deploying to a production environment where assets will be
# uploaded to and served from a CDN or proxy server.
darkroom.dump('output/dir',
  clear: true,            # Delete contents of output/dir before dumping
  include_pristine: true, # Include pristine assets (if preparing for CDN upload, files like
)                         # /favicon.ico or /robots.txt should be left out)
```

Note that assets paths across all load path directories must be globally unique (e.g. the existence of both
`app/assets/app.js` and `vendor/assets/app.js` will result in an error).

To work with assets:

```ruby
# Get the external path that will be used by HTTP requests.
path = darkroom.asset_path('/js/app.js') # => '/static/js/app-<fingerprint>.js'

# Retrieve the Asset object associated with a path.
asset = darkroom.asset(path)

# Getting paths directly from an Asset object will not include any host or prefix.
assest.path           # => '/js/app.js'
assest.path_versioned # => '/js/app-<fingerprint>.js'

asset.content_type # => 'application/javascript'
asset.content      # Content of processed /js/app.js file

asset.headers                   # => {'Content-Type' => 'application/javascript',
                                #     'Cache-Control' => 'public, max-age=31536000'}
asset.headers(versioned: false) # => {'Content-Type' => 'application/javascript',
                                #     'ETag' => '<fingerprint>'}
```

## Asset Bundling

CSS and JavaScript assets specify their dependencies by way of each language's native import statement. Each
import statement is replaced with content of the referenced asset. Example:

```javascript
// Unprocessed /api.js
function api() {
  console.log('API called!')
}

// Unprocessed /app.js
import '/api.js'

api()

// Processed /app.js
function api() {
  console.log('API called!')
}


api()
```

The same applies for CSS files. Example:

```css
/* Unprocessed /header.css */
header {
  background: #f1f1f1;
}

/* Unprocessed /app.css */
@import '/header.css';

body {
  background: #fff;
}

/* Processed /app.css */
header {
  background: #f1f1f1;
}


body {
  background: #fff;
}
```

Imported assets can also contain import statements, and those assets are all included in the base asset.
Imports can even be cyclical. If `asset-a.css` imports `asset-b.css` and vice-versa, each asset will simply
contain the content of both of those assets (though order will be different as an asset's own content always
comes after any imported assets' contents).

## Extending

Darkroom is extensible. Support for arbitrary file types can be added as follows (all named parameters are
optional):

```ruby
Darkroom::Asset.add_spec('.extension1', 'extension2', '...', 'content/type',
  dependency_regex: /import (?<path>.*)/, # Regex for identifying dependencies for bundling;
                                          # must include `path` named capture group
  compile_lib: 'some-compile-lib',        # Name of library required for compilation
  compile: -> (path, content) { '...' },  # Proc that returns compiled content
  minify_lib: 'some-minify-lib',          # Name of library required for minification
  minify: -> (content) { '...' },         # Proc that returns minified content
)

```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/npickens/darkroom.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
