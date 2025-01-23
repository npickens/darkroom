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
    # [library] Name of the library that's missing.
    # [need] Reason the library is needed ('pre-process', 'post-process', or 'minify').
    # [extension] Extension of the type of asset that needs the library.
    #
    def initialize(library, need, extension)
      super("Cannot #{need} #{extension} file(s): #{library} library not available [hint: try adding "\
        "gem('#{library}') to your Gemfile]")

      @library = library
      @need = need
      @extension = extension
    end
  end
end
