# frozen_string_literal: true

class Darkroom
  ##
  # Error class used when an asset requested explicitly or specified as a dependency of another cannot be
  # found.
  #
  class AssetNotFoundError < StandardError
    attr_reader(:path)

    ##
    # Creates a new instance.
    #
    # * +path+ - The path of the asset that cannot be found.
    # * +referenced_from+ - The path of the asset the not-found asset was referenced from.
    # * +referenced_from_line+ - The line number where the not-found asset was referenced.
    #
    def initialize(path, referenced_from = nil, referenced_from_line = nil)
      @path = path
      @referenced_from = referenced_from
      @referenced_from_line = referenced_from_line
    end

    ##
    # Returns a string representation of the error.
    #
    def to_s
      "Asset not found#{
        " (referenced from #{@referenced_from}:#{@referenced_from_line || '?'})" if @referenced_from
      }: #{@path}"
    end
  end
end
