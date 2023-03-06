# frozen_string_literal: true

require_relative('asset_error')

class Darkroom
  ##
  # Error class used when a reference is made to a file with an unrecognized extension.
  #
  class UnrecognizedExtensionError < AssetError
    ##
    # Creates a new instance.
    #
    # [file] File with the unrecognized extension.
    # [source_path] Path of the asset that contains the error.
    # [source_line_num] Line number in the asset where the error is located.
    #
    def initialize(file, source_path = nil, source_line_num = nil)
      super('File extension not recognized', file, source_path, source_line_num)
    end
  end
end
