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
| APNG       | image/apng       | .apng        |
| AVIF       | image/avif       | .avif        |
| CSS        | text/css         | .css         |
| GIF        | image/gif        | .gif         |
| HTML       | text/html        | .htm, .html  |
| HTX        | text/javascript  | .htx         |
| ICO        | image/x-icon     | .ico         |
| JavaScript | text/javascript  | .js          |
| JPEG       | image/jpeg       | .jpg, .jpeg  |
| JSON       | application/json | .json        |
| PNG        | image/png        | .png         |
| SVG        | image/svg+xml    | .svg         |
| Text       | text/plain       | .txt         |
| WebP       | image/webp       | .webp        |
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
gem('htx')    # HTX compilation
gem('sassc')  # CSS minification
gem('terser') # JavaScript and HTX minification
```

## Usage

To create and start using a Darkroom instance, specify one or more load paths (all keyword arguments are
optional):

```ruby
darkroom = Darkroom.new('app/assets', 'vendor/assets', '...',
  hosts: [                           # Hosts to prepend to asset paths (useful in production when
    'https://cname1.cdn.com',        #   assets are served from a CDN with multiple cnames);
    'https://cname2.cdn.com',        #   hosts are chosen round-robin per thread
    '...',
  ],
  prefix: '/static',                 # Prefix to add to all asset paths
  pristine: ['/google-verify.html'], # Paths with no prefix or versioning (assets such as
                                     #   /favicon.ico and /robots.txt are included automatically)
  entries: /^\/controllers\//,       # Assets that will be directly accessed (fewer means better
                                     #   performance); can be a string, regex, or array of such
  minify: true,                      # Minify assets that can be minified
  minified: /(\.|-)min\.\w+$/,       # Files to skip minification on when minify: true; can be a
                                     #   string, regex, or array of such
  min_process_interval: 1,           # Minimum time that must elapse between process calls
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
path = darkroom.asset_path('/js/app.js')           # => "/static/js/app-[fingerprint].js"
integrity = darkroom.asset_integrity('/js/app.js') # => "sha384-[hash]"

# Retrieve the Asset object associated with a path.
asset = darkroom.asset(path)

# Prefix (if set on the Darkroom instance) is included in the unversioned and versioned paths.
assest.path                     # => "/js/app.js"
assest.path_unversioned         # => "/static/js/app.js"
assest.path_versioned           # => "/static/js/app-[fingerprint].js"

asset.content                   # Content of processed /js/app.js file

asset.content_type              # => "text/javascript"
asset.binary?                   # => false
asset.font?                     # => false
asset.image?                    # => false
asset.entry?                    # => true

asset.error?                    # => true
asset.errors                    # => [#<Darkroom::AssetError ...>, ...]

asset.fingerprint               # => "[MD5 hash of asset content]"
asset.headers                   # => {"Content-Type" => "text/javascript",
                                #     "Cache-Control" => "public, max-age=31536000"}
asset.headers(versioned: false) # => {"Content-Type" => "text/javascript",
                                #     "ETag" => "[fingerprint]"}

asset.integrity                 # => "sha384-[hash]"
asset.integrity(:sha256)        # => "sha256-[hash]"
asset.integrity(:sha384)        # => "sha384-[hash]"
asset.integrity(:sha512)        # => "sha512-[hash]"
```

## Asset Bundling

CSS and JavaScript assets specify their dependencies by way of each language's native import statement. Each
import statement is replaced with the content of the imported asset. Example:

```css
/* Unprocessed /header.css */
header { background: #f1f1f1; }
```

```css
/* Unprocessed /app.css */
@import '/header.css';

body { background: #fff; }
```

```css
/* Processed /app.css */
header { background: #f1f1f1; }

body { background: #fff; }
```

Imported assets can also contain import statements, and those assets are all included in the base asset.
Imports can even be cyclical. If `asset-a.css` imports `asset-b.css` and vice-versa, each asset will simply
contain the content of both of those assets (though order will be different as an asset's own content always
comes after any imported assets' contents).

By default, JavaScript files are concatenated in the same way that CSS files are. Example:

```javascript
// Unprocessed /api.js
function API() { console.log('API called!') }
```

```javascript
// Unprocessed /app.js
import '/api.js'

API()
```

```javascript
// Processed /app.js
function API() { console.log('API called!') }

API()
```

Alternatively, setting `Darkroom.javascript_iife = true` will cause JavaScript assets to be compiled to a
series of IIFEs that provide the same encapsulation as native ES6 modules (indentation is not quite as
pretty as shown here, but has been altered here for readability):

```javascript
// Unprocessed /api.js
export function API() { console.log('API called!') }
```

```javascript
// Unprocessed /app.js
import {API} from '/api.js'

API()
```

```javascript
// Processed /app.js
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
  ['/api.js', $import => {
    function API() { console.log('API called!') }

    return Object.seal({
      API: API,
    })
  }],

  ['/app.js', $import => {
    let API; $import('/api.js', m => API = m.API)

    API()

    return Object.seal({})
  }],
)
```

## Asset References

Asset paths and content can be inserted into an asset by referencing an asset's path and including a query
parameter.

| String                           | Result                            |
|----------------------------------|-----------------------------------|
| /logo.svg?asset-path             | /prefix/logo-[fingerprint].svg    |
| /logo.svg?asset-path=versioned   | /prefix/logo-[fingerprint].svg    |
| /logo.svg?asset-path=unversioned | /prefix/logo.svg                  |
| /logo.svg?asset-content          | data:image/svg+xml;base64,[data]  |
| /logo.svg?asset-content=base64   | data:image/svg+xml;base64,[data]  |
| /logo.svg?asset-content=utf8     | data:image/svg+xml;utf8,\<svg>... |

Where these get recognized is specific to each asset type.

* **CSS** - Within `url(...)`, which may be unquoted or quoted with single or double quotes.
* **HTML** - Values of `href` and `src` attributes on `a`, `area`, `audio`, `base`, `embed`, `iframe`,
  `img`, `input`, `link`, `script`, `source`, `track`, and `video` tags.
* **HTX** - Same behavior as HTML.

HTML assets additionally support the `?asset-content=displace` query parameter for use with `<link>`,
`<script>`, and `<img>` tags with CSS, JavaScript, and SVG asset references, respectively. The entire tag is
replaced appropriately.

```html
<!-- Source -->
<head>
  <title>My App</title>
  <link href='/app.css?asset-content=displace' type='text/css'>
  <script src='/app.js?asset-content=displace'></script>
</head>

<body>
  <img src='/logo.svg?asset-content=displace'>
</body>
```

```html
<!-- Result -->
<head>
  <title>My App</title>
  <style>/* Content of /app.css */</style>
  <script>/* Content of /app.js */</script>
</head>

<body>
  <svg><!-- ... --></svg>
</body>
```

## Extending

Darkroom is extensible. Support for arbitrary file types can be added by specifying one or more extensions
and a content type:

```ruby
Darkroom.register('.ext1', '.ext2', '...', 'content/type')
```

### DSL

For more advanced functionality, the DSL can be used one of three ways. With a block:

```ruby
Darkroom.register('.ext1', '.ext2', '...') do
  # ...
end
```

Or with a class that extends `Darkroom::Delegate`:

```ruby
class MyDelegate < Darkroom::Delegate
  # ...
end

Darkroom.register('.ext1', '.ext2', '...', MyDelegate)
```

Or with both:

```ruby
class MyDelegate < Darkroom::Delegate
  # ...
end

Darkroom.register('.ext1', '.ext2', '...', MyDelegate) do
  # Extend MyDelegate
end
```

The DSL supports basic parsing via regular expressions, with special behavior for import statements and
references. Compilation, finalization, and minification behavior can also be configured.

#### Content Type

```ruby
Darkroom.register('.ext1', '.ext2', '...') do
  content_type('content/type') # HTTP MIME type string.

  # ...
end
```

#### Imports

Imports are references to other assets, identified via regex, which get prepended to an asset's own content.
The regex requires a named component, `path`, as it is used internally to determine the asset being imported
(leveraging `Asset::QUOTED_PATH_REGEX` within one's own regex is helpful).

A block is optional, but can be used to accumulate parse data and/or override the default behavior of
removing an import statement altogether by returning a string to replace it with.

```ruby
Darkroom.register('.ext1', '.ext2', '...') do
  # ...

  # The (optional) block is passed three named arguments:
  #   parse_data: - Hash for storing data across calls to this and other parse handlers.
  #   match:      - MatchData object from the match against the provided regex.
  #   asset:      - Asset object of the asset being imported.
  import(/import #{Asset::QUOTED_PATH_REGEX.source};/) do |parse_data:, match:, asset:|
    parse_data[:imports] ||= []          # Accumulate and use arbitrary parse data.
    parse_data[:imports] << match[:path] # Use the MatchData object of the regex match.

    if asset.binary?                     # Access the Asset object of the imported asset.
      error('Binary asset not allowed!') # Halt execution of the block and record an error.
    end

    # Return nil for default behavior (import statement is removed).
    nil

    # ...Or return a string as the replacement for the import statement.
    "/* [#{asset.path}] */"
  end
end
```

#### References

References are non-import references to other assets, identified via regex, which result in either the
asset's path or content being inserted in place. The regex requires named components `quote`, `quoted`,
`path`, `entity`, and `format`, as these are used internally to determine the asset being referenced and how
it should be treated (leveraging `Asset::REFERENCE_REGEX` within one's own regex is helpful). See the [Asset
References](#asset-references) section for more detail.

* `quote` - The type of quote used (e.g. `'` or `"`)
* `quoted` - The portion of text within the `quote`s
* `path` - The path of the asset
* `entity` - Either 'path' or 'content'
* `format` - Format of the path or content
  * If `entity` == 'path' - Either 'versioned' or 'unversioned'
  * If `entity` == 'content' - One of 'base64', 'utf8', or 'displace'

A block is optional, but can be used to accumulate parse data and/or override the default behavior of
removing an import statement altogether by returning a string to replace it with.

```ruby
Darkroom.register('.ext1', '.ext2', '...') do
  # ...

  reference_regex = /ref=#{Asset::REFERENCE_REGEX.source}/x

  # The (optional) block is passed four named arguments:
  #   parse_data: - Hash for storing data across calls to this and other parse handlers.
  #   match:      - MatchData object from the match against the provided regex.
  #   asset:      - Asset object of the asset being referenced.
  #   format:     - Format of the reference (see Asset::REFERENCE_FORMATS).
  reference(reference_regex) do |parse_data:, match:, asset:, format:|
    parse_data[:refs] ||= []          # Accumulate and use arbitrary parse data.
    parse_data[:refs] << match[:path] # Use the MatchData object of the regex match.

    if format == 'base64'           # See Asset References section for format details.
      error('Format must be utf8!') # Halt execution of the block and register an error.
    end

    # Return nil for default behavior (path or content is substituted based on format).
    nil

    # ...Or return a string to use in lieu of default substitution.
    asset.content.gsub('#', '%23') if format == 'utf8'

    # ...Or return nil or a string, a start index, and an end index of text to substitute.
    ["[ref]#{asset.content.gsub('#', '%23')}[/ref]", match.begin(0), match.end(0)]
  end
end
```

#### Parsing

More generalized parsing of any asset-specific text of interest can be performed with `parse` calls, which
take a name, regex, and block that returns the substitution for the matched text.


```ruby
Darkroom.register('.ext1', '.ext2', '...') do
  # ...

  # The block is passed two named arguments:
  #   parse_data: - Hash for storing data across calls to this and other parse handlers.
  #   match:      - MatchData object from the match against the provided regex.
  parse(:exports, /export (?<name>.+)/) do |parse_data:, match:|
    parse_data[:exports] ||= []          # Accumulate and use arbitrary parse data.
    parse_data[:exports] << match[:name] # Use the MatchData object of the regex match.

    # Return nil for default behavior (matched text is removed).
    nil

    # ...Or return a string as the replacement for the matched text.
    "exports.#{match[:name]} = "

    # ...Or return a string, a start index, and an end index of text to substitute.
    [match[:name].upcase, match.begin(:name), match.end(:name)]
  end

  # Any number of parse statements are allowed and are run in the order they are declared.
  parse(:something_else, /.../) do |parse_data:, match:|
    # ...
  end
end
end
```

#### Compile

Compilation allows for a library to require (optional), a delegate to use after compilation (optional), and
a block that returns the compiled version of the asset's own content.

```ruby
Darkroom.register('.ext1', '.ext2', '...') do
  # ...

  # The block is passed three named arguments:
  #   parse_data:  - Hash of data collected during parsing.
  #   path:        - Path of the asset being compiled.
  #   own_content: - Asset's own content (without imports).
  compile(lib: 'compile_lib', delegate: SomeDelegate) do |parse_data:, path:, own_content:|
    CompileLib.compile(own_content)
  end
end
```

#### Finalize

Finalization happens once an asset is fully processed and compiled (though before minification). A library
can be provided to require (optional) and the block should return the finalized version of the asset's
compiled content.

```ruby
Darkroom.register('.ext1', '.ext2', '...') do
  # ...

  # The block is passed three named arguments:
  #   parse_data: - Hash of data collected during parsing.
  #   path:       - Path of the asset being finalized.
  #   content:    - Asset's compiled content (with imports prepended).
  finalize(lib: 'finalize_lib') do |parse_data:, path:, content:|
    FinalizeLib.finalize(content)
  end
end
```

#### Minify

Minification is the very last thing that happens to an asset's content, though it will only happen if
minification is enabled on the Darkroom instance. A library can be provided to require (optional) and the
block should return the minified version of the asset's finalized content.

```ruby
Darkroom.register('.ext1', '.ext2', '...') do
  # ...

  # The block is passed three named arguments:
  #   parse_data: - Hash of data collected during parsing.
  #   path:       - Path of the asset being finalized.
  #   content:    - Asset's finalized content.
  minify(lib: 'minify_lib') do |parse_data:, path:, content:|
    MinifyLib.compress(content)
  end
end

```

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/npickens/darkroom.

## License

The gem is available as open source under the terms of the
[MIT License](https://opensource.org/licenses/MIT).
