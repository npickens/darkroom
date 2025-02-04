# frozen_string_literal: true

require_relative('asset_error')

class Darkroom
  # Error class used when an asset requested explicitly or specified as a dependency of another doesn't
  # exist.
  class AssetNotFoundError < AssetError
    # Public: Create a new instance.
    #
    # path            - String path of asset that doesn't exist.
    # source_path     - String path of the asset that contains the error.
    # source_line_num - Integer line number in the asset file where the error is located.
    def initialize(path, source_path = nil, source_line_num = nil)
      super('Asset not found', path, source_path, source_line_num)
    end
  end
end
