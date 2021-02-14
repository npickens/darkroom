# frozen_string_literal: true

class Darkroom
  ##
  # Error class used when an asset exists in multiple load paths.
  #
  class DuplicateAssetError < StandardError
    attr_reader(:path, :first_load_path, :second_load_path)

    ##
    # Creates a new instance.
    #
    # * +path+ - The path of the asset that has the same path as another asset.
    # * +first_load_path+ - The load path where the first asset with the path was found.
    # * +second_load_path+ - The load path where the second asset with the path was found.
    #
    def initialize(path, first_load_path, second_load_path)
      @path = path
      @first_load_path = first_load_path
      @second_load_path = second_load_path
    end

    ##
    # Returns a string representation of the error.
    #
    def to_s
      "Asset file exists in both #{@first_load_path} and #{@second_load_path}: #{@path}"
    end
  end
end
