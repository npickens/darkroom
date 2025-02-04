# frozen_string_literal: true

require_relative('asset_error')

class Darkroom
  # Error class used when a reference is made to a file with an unrecognized extension.
  class UnrecognizedExtensionError < AssetError
    # Public: Create a new instance.
    #
    # file            - String file path with the unrecognized extension.
    # source_path     - String path of the asset that contains the error.
    # source_line_num - Integer line number in the asset file where the error is located.
    def initialize(file, source_path = nil, source_line_num = nil)
      super('File extension not recognized', file, source_path, source_line_num)
    end
  end
end
