# frozen_string_literal: true

require_relative('html_delegate')
require_relative('javascript_delegate')

class Darkroom
  ##
  # Delegate for handling HTX-specific asset processing.
  #
  class HTXDelegate < HTMLDelegate
    compile(lib: 'htx', delegate: JavaScriptDelegate) do |parse_data:, path:, own_content:|
      module_supported = false

      if defined?(HTX::VERSION)
        major, minor, patch = HTX::VERSION.split('.').map(&:to_i)
        module_supported = major > 0 || minor > 1 || (minor == 1 && patch >= 1)
      end

      if module_supported
        HTX.compile(path, own_content, as_module: Darkroom.javascript_iife)
      else
        HTX.compile(path, own_content)
      end
    end
  end
end
