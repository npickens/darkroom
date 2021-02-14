# frozen_string_literal: true

class Darkroom
  ##
  # Error class used when a needed library cannot be loaded. See Asset#require_libs.
  #
  class MissingLibraryError < StandardError
    attr_reader(:library, :need, :extension)

    ##
    # Creates a new instance.
    #
    # * +library+ - The name of the library that's missing.
    # * +need+ - The reason the library is needed ('compile' or 'minify').
    # * +extension+ - The extenion of the type of asset that needs the library.
    #
    def initialize(library, need, extension)
      @library = library
      @need = need
      @extension = extension
    end

    ##
    # Returns a string representation of the error.
    #
    def to_s
      "Cannot #{@need} #{@extension} file(s): #{@library} library not available"
    end
  end
end
