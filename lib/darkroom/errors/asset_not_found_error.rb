# frozen_string_literal: true

require_relative('asset_error')

class Darkroom
  ##
  # Error class used when an asset requested explicitly or specified as a dependency of another doesn't
  # exist.
  #
  class AssetNotFoundError < AssetError
    ##
    # Creates a new instance.
    #
    # * +path+ - Path of asset that doesn't exist.
    # * +source_path+ - Path of the asset that contains the error (optional).
    # * +source_line_num+ - Line number in the asset where the error is located (optional).
    #
    def initialize(path, source_path = nil, source_line_num = nil)
      super('Asset not found', path, source_path, source_line_num)
    end
  end
end
