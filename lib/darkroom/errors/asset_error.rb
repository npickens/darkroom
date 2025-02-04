# frozen_string_literal: true

class Darkroom
  # General error class used for errors encountered while processing an asset.
  class AssetError < StandardError
    attr_reader(:detail, :source_path, :source_line_num)

    # Public: Create a new instance.
    #
    # message         - String description of the error.
    # detail          - String additional error detail.
    # source_path     - String path of the asset that contains the error.
    # source_line_num - Integer line number in the asset file where the error was located.
    def initialize(message, detail, source_path = nil, source_line_num = nil)
      super("#{"#{source_path}:#{source_line_num || '?'}: " if source_path}#{message}: #{detail}")

      @detail = detail
      @source_path = source_path
      @source_line_num = source_line_num
    end
  end
end
