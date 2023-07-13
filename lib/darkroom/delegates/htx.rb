# frozen_string_literal: true

require_relative('html')
require_relative('javascript')

class Darkroom
  class HTXDelegate < HTMLDelegate
    compile(lib: 'htx', delegate: JavaScriptDelegate) do |parse_data:, path:, own_content:|
      HTX.compile(path, own_content)
    end
  end
end
