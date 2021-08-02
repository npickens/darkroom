# frozen_string_literal: true

require_relative('../asset')

class Darkroom
  class Asset
    HTMLDelegate = Delegate.new(
      content_type: 'text/html',
      reference_regex: %r{
        <(?<tag>a|area|audio|base|embed|iframe|img|input|link|script|source|track|video)\s+[^>]*
        (?<attr>href|src)=#{REFERENCE_PATH.source}[^>]*>
      }x.freeze,

      validate_reference: ->(asset, match, format) do
        return unless format == 'displace'

        if match[:tag] == 'link'
          'Asset type must be text/css' unless asset.content_type == 'text/css'
        elsif match[:tag] == 'script'
          'Asset type must be text/javascript' unless asset.content_type == 'text/javascript'
        elsif match[:tag] == 'img'
          'Asset type must be image/svg+xml' unless asset.content_type == 'image/svg+xml'
        else
          "Cannot displace <#{match[:tag]}> tags"
        end
      end,

      reference_content: ->(asset, match, format) do
        case format
        when 'displace'
          if match[:tag] == 'link' && asset.content_type == 'text/css'
            "<style>#{asset.content}</style>"
          elsif match[:tag] == 'script' && asset.content_type == 'text/javascript'
            offset = match.begin(0)

            "#{match[0][0..(match.begin(:attr) - 2 - offset)]}"\
            "#{match[0][(match.end(:quoted) + match[:quote].size - offset)..(match.end(0) - offset)]}"\
            "#{asset.content}"
          elsif match[:tag] == 'img' && asset.content_type == 'image/svg+xml'
            asset.content
          end
        when 'utf8'
          quote = match[:quote] == '' ? Asset::DEFAULT_QUOTE : match[:quote]

          content = asset.content.gsub('#', '%23')
          content.gsub!(quote, quote == "'" ? '"' : "'")

          content
        end
      end,
    )
  end
end
