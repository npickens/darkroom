# frozen_string_literal: true

require_relative('../asset')

class Darkroom
  ##
  # Error class used when an asset's path contains one or more invalid characters.
  #
  class InvalidPathError < StandardError
    attr_reader(:path, :index)

    ##
    # Creates a new instance.
    #
    # [path] Path of the asset with the invalid character(s).
    # [index] Position of the first bad character in the path.
    #
    def initialize(path, index)
      super("Asset path contains one or more invalid characters (#{Asset::DISALLOWED_PATH_CHARS}): #{path}")

      @path = path
      @index = index
    end
  end
end
