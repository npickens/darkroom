# frozen_string_literal: true

require_relative('../asset')
require_relative('../delegate')

class Darkroom
  # Delegate for handling CSS-specific asset processing.
  class CSSDelegate < Delegate
    IMPORT_REGEX = /
      (?<=^|;)[^\S\n]*
      @import\s+#{Asset::QUOTED_PATH_REGEX.source}
      [^\S\n]*;[^\S\n]*(\n|\Z)
    /x

    REFERENCE_REGEX = /url\(\s*#{Asset::REFERENCE_REGEX.source}\s*\)/x

    content_type('text/css')

    import(IMPORT_REGEX)

    reference(REFERENCE_REGEX) do |parse_data:, match:, asset:, format:|
      if format == 'displace'
        error('Cannot displace in CSS files')
      elsif !asset.image? && !asset.font?
        error('Referenced asset must be an image or font type')
      elsif format == 'utf8'
        content = asset.content.dup

        content.gsub!('#', '%23')
        content.gsub!('\'', '\\\\\'')
        content.gsub!('"', '\\"')
        content.gsub!("\n", "\\\n")

        content
      end
    end

    minify(lib: 'sassc') do |parse_data:, path:, content:|
      SassC::Engine.new(content, style: :compressed).render
    end
  end
end
