# frozen_string_literal: true

require_relative('../asset')
require_relative('../delegate')

class Darkroom
  # Delegate for handling HTML-specific asset processing.
  class HTMLDelegate < Delegate
    REFERENCE_REGEX = /
      <(?<tag>a|area|audio|base|embed|iframe|img|input|link|script|source|track|video)\s+[^>]*
      (?<attr>href|src)=#{Asset::REFERENCE_REGEX.source}[^>]*>
    /x

    content_type('text/html')

    reference(REFERENCE_REGEX) do |parse_data:, match:, asset:, format:|
      case format
      when 'displace'
        case match[:tag]
        when 'link'
          if asset.content_type == 'text/css'
            "<style>#{asset.content}</style>"
          else
            error('Asset content type must be text/css')
          end
        when 'script'
          if asset.content_type == 'text/javascript'
            offset = match.begin(0)

            "#{match[0][0..(match.begin(:attr) - 2 - offset)]}" \
            "#{match[0][(match.end(:quoted) + match[:quote].size - offset)..(match.end(0) - offset)]}" \
            "#{asset.content}"
          else
            error('Asset content type must be text/javascript')
          end
        when 'img'
          if asset.content_type == 'image/svg+xml'
            asset.content(minified: false)
          else
            error('Asset content type must be image/svg+xml')
          end
        else
          error("Cannot displace <#{match[:tag]}> tags")
        end
      when 'utf8'
        quote = match[:quote] == '' ? Asset::DEFAULT_QUOTE : match[:quote]

        content = asset.content.dup
        content.gsub!('#', '%23')
        content.gsub!(quote, quote == '"' ? '&#34;' : '&#39;')

        content
      end
    end
  end
end
