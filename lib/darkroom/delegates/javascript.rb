# frozen_string_literal: true

require_relative('../asset')

class Darkroom
  class Asset
    JavaScriptDelegate = Delegate.new(
      content_type: 'text/javascript',
      import_regex: /^ *import +#{QUOTED_PATH.source} *;? *(\n|$)/.freeze,
      minify_lib: 'uglifier',
      minify: ->(content) do
        Uglifier.compile(content, harmony: true)
      end,
    )
  end
end
