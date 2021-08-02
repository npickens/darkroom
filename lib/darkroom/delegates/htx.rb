# frozen_string_literal: true

require_relative('../asset')
require_relative('html')
require_relative('javascript')

class Darkroom
  class Asset
    HTXDelegate = Delegate.new(
      content_type: JavaScriptDelegate.content_type,
      import_regex: HTMLDelegate.import_regex,
      reference_regex: HTMLDelegate.reference_regex,
      validate_reference: HTMLDelegate.validate_reference,
      reference_content: HTMLDelegate.reference_content,
      compile_lib: 'htx',
      compile: ->(path, content) { HTX.compile(path, content) },
      minify_lib: JavaScriptDelegate.minify_lib,
      minify: JavaScriptDelegate.minify,
    )
  end
end
