# Darkroom

Darkroom is a fast, lightweight, and straightforward web asset management library. Processed assets are all
stored in and served directly from memory rather than being written to disk (though a dump to disk can be
performed for upload to a CDN or proxy server in production environments); this keeps asset management
simple and performant in development. Darkroom also supports asset bundling for CSS and JavaScript using
each language's native import statement syntax.

The following file types are supported out of the box, though support for others can be added (see the
[Extending](#extending) section):

| Name       | Content Type     | Extension(s) |
|------------|------------------|--------------|
| CSS        | text/css         | .css         |
| HTML       | text/html        | .htm, .html  |
| HTX        | text/javascript  | .htx         |
| ICO        | image/x-icon     | .ico         |
| JavaScript | text/javascript  | .js          |
| JPEG       | image/jpeg       | .jpg, .jpeg  |
| JSON       | application/json | .json        |
| PNG        | image/png        | .png         |
| SVG        | image/svg+xml    | .svg         |
| Text       | text/plain       | .txt         |
| WOFF       | font/woff        | .woff        |
| WOFF2      | font/woff2       | .woff2       |

## Installation

Add this line to your Gemfile:

```ruby
gem('darkroom')
```

Or install manually on the command line:

```bash
gem install darkroom
```

Darkroom depends on a few other gems for compilation and minification of certain asset types, but does not
explicitly include them as dependencies since need for them varies from project to project. As such, if your
project includes HTX templates or you wish to minify CSS and/or JavaScript assets, the following will need
to be added to your Gemfile:

```ruby
gem('htx')      # HTX compilation
gem('sassc')    # CSS minification
gem('uglifier') # JavaScript and HTX minification
```

## Usage

To create and start using a Darkroom instance, specify one or more load paths (all other arguments are
optional):

```ruby
darkroom = Darkroom.new('app/assets', 'vendor/assets', '...',
  hosts: [                             # Hosts to prepend to asset paths (useful in production
    'https://cname1.cdn.com',          # when assets are served from a CDN with multiple
    'https://cname2.cdn.com',          # cnames); hosts are chosen round-robin per thread
    '...',
  ],
  prefix: '/static',                   # Prefix to add to all asset paths
  pristine: ['/google-verify.html'],   # Paths with no prefix or versioning (/favicon.ico,
                                       # /mask-icon.svg, /humans.txt, and /robots.txt are
                                       # included automatically)
  minify: true,                        # Minify assets that can be minified
  minified_pattern: /(\.|-)min\.\w+$/, # Files to skip minification on when minify: true
  internal_pattern: /^\/components\//, # Files to disallow direct external access to (they can
                                       # still be imported into other assets)
  min_process_interval: 1,             # Minimum time that must elapse between process calls
)
```

Note that assets paths across all load path directories must be globally unique (e.g. the existence of both
`app/assets/app.js` and `vendor/assets/app.js` will result in an error).

Darkroom will never update assets without explicitly being told to do so. The following call should be made
once when the app is started and additionally at the beginning of each web request in development to refresh
any modified assets:

```ruby
darkroom.process
```

Alternatively, assets can be dumped to disk when deploying to a production environment where assets will be
uploaded to and served from a CDN or proxy server:

```ruby
darkroom.dump('output/dir',
  clear: true,            # Delete contents of output/dir before dumping
  include_pristine: true, # Include pristine assets (if preparing for CDN upload, files like
)                         # /favicon.ico or /robots.txt should be left out)
```

To work with assets:

```ruby
# A Darkroom instance has a few convenience helper methods.
path = darkroom.asset_path('/js/app.js')           # => '/static/js/app-[fingerprint].js'
integrity = darkroom.asset_integrity('/js/app.js') # => 'sha384-[hash]'

# Retrieve the Asset object associated with a path.
asset = darkroom.asset(path)

# Prefix (if set on the Darkroom instance) is included in the unversioned and versioned paths.
assest.path                     # => '/js/app.js'
assest.path_unversioned         # => '/static/js/app.js'
assest.path_versioned           # => '/static/js/app-[fingerprint].js'

asset.content_type              # => 'text/javascript'
asset.content                   # Content of processed /js/app.js file

asset.headers                   # => {'Content-Type' => 'text/javascript',
                                #     'Cache-Control' => 'public, max-age=31536000'}
asset.headers(versioned: false) # => {'Content-Type' => 'text/javascript',
                                #     'ETag' => '[fingerprint]'}

asset.integrity                 # => 'sha384-[hash]'
asset.integrity(:sha256)        # => 'sha256-[hash]'
asset.integrity(:sha512)        # => 'sha512-[hash]'
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
