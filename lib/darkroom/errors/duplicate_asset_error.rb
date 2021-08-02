# frozen_string_literal: true

class Darkroom
  ##
  # Error class used when an asset exists under multiple load paths.
  #
  class DuplicateAssetError < StandardError
    attr_reader(:path, :first_load_path, :second_load_path)

    ##
    # Creates a new instance.
    #
    # * +path+ - Path of the asset that exists under multiple load paths.
    # * +first_load_path+ - Load path where the asset was first found.
    # * +second_load_path+ - Load path where the asset was subsequently found.
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
