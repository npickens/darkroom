# frozen_string_literal: true

require_relative('asset_error')

class Darkroom
  # Error class used when an asset reference results in a circular reference chain.
  class CircularReferenceError < AssetError
    # Public: Create a new instance.
    #
    # snippet         - String snippet showing the reference.
    # source_path     - String path of the asset that contains the error.
    # source_line_num - Integer line number in the asset file where the error is located.
    def initialize(snippet, source_path, source_line_num)
      super('Reference would result in a circular reference chain', snippet, source_path, source_line_num)
    end
  end
end
