# frozen_string_literal: true

class Darkroom
  # Error class used when a needed library cannot be loaded. See Asset#require_libs.
  class MissingLibraryError < StandardError
    attr_reader(:library, :need, :extension)

    # Public: Create a new instance.
    #
    # library   - String name of the library that's missing.
    # need      - Symbol or String reason the library is needed (:compile, :finalize, or :minify).
    # extension - String extension of the type of asset that needs the library.
    def initialize(library, need, extension)
      super("Cannot #{need} #{extension} files: '#{library}' library not available [hint: try adding " \
        "gem('#{library}') to your Gemfile]")

      @library = library
      @need = need
      @extension = extension
    end
  end
end
