# frozen_string_literal: true

require_relative('../asset')

class Darkroom
  class Asset
    CSSDelegate = Delegate.new(
      content_type: 'text/css',
      import_regex: /^ *@import +#{QUOTED_PATH.source} *; *(\n|$)/.freeze,
      reference_regex: /url\(\s*#{REFERENCE_PATH.source}\s*\)/x.freeze,

      validate_reference: ->(asset, match, format) do
        if format == 'displace'
          'Cannot displace in CSS files'
        elsif !asset.image? && !asset.font?
          'Referenced asset must be an image or font type'
        end
      end,

      reference_content: ->(asset, match, format) do
        if format == 'utf8'
          content = asset.content.gsub('#', '%23')
          content.gsub!(/(['"])/, '\\\\\1')
          content.gsub!("\n", "\\\n")

          content
        end
      end,

      minify_lib: 'sassc',
      minify: ->(content) do
        SassC::Engine.new(content, style: :compressed).render
      end,
    )
  end
end
