# frozen_string_literal: true

require_relative('../asset')
require_relative('../delegate')

class Darkroom
  class JavaScriptDelegate < Delegate
    IMPORT_REGEX = /
      (?<=^|;|})[^\S\n]*
      import\s+#{Asset::QUOTED_PATH_REGEX.source}
      [^\S\n]*;?[^\S\n]*(\n|\Z)
    /x.freeze

    content_type('text/javascript')

    import(IMPORT_REGEX)

    minify(lib: 'terser') do |parse_data:, path:, content:|
      Terser.compile(content)
    end
  end
end
