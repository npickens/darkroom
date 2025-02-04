# frozen_string_literal: true

class Darkroom
  # Error class used when the same asset path exists under multiple load paths.
  class DuplicateAssetError < StandardError
    attr_reader(:path, :first_load_path, :second_load_path)

    # Public: Create a new instance.
    #
    # path             - String path of the asset that exists under multiple load paths.
    # first_load_path  - String load path where the asset was first found.
    # second_load_path - String load path where the asset was subsequently found.
    def initialize(path, first_load_path, second_load_path)
      super("Asset file exists in both #{first_load_path} and #{second_load_path}: #{path}")

      @path = path
      @first_load_path = first_load_path
      @second_load_path = second_load_path
    end
  end
end
