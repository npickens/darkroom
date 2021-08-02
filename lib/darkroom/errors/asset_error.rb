# frozen_string_literal: true

class Darkroom
  ##
  # General error class used for errors encountered while processing an asset.
  #
  class AssetError < StandardError
    attr_reader(:detail, :source_path, :source_line_num)

    ##
    # Creates a new instance.
    #
    # * +message+ - Description of the error.
    # * +detail+ - Additional detail about the error.
    # * +source_path+ - Path of the asset that contains the error (optional).
    # * +source_line_num+ - Line number in the asset where the error is located (optional).
    #
    def initialize(message, detail, source_path = nil, source_line_num = nil)
      super(message)

      @detail = detail
      @source_path = source_path
      @source_line_num = source_line_num
    end

    ##
    # Returns a string representation of the error.
    #
    def to_s
      "#{"#{@source_path}:#{@source_line_num || '?'}: " if @source_path}#{super}: #{@detail}"
    end
  end
end
