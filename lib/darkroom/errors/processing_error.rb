# frozen_string_literal: true

class Darkroom
  # Error class used to wrap all accumulated errors encountered during asset processing.
  class ProcessingError < StandardError
    include(Enumerable)

    # Public: Create a new instance.
    #
    # errors - Error or Array of errors.
    def initialize(errors)
      @errors = Array(errors)

      super("Errors were encountered while processing assets:\n  #{@errors.map(&:to_s).join("\n  ")}")
    end

    # Public: Iterate over each error.
    #
    # block - Block to call and pass each error to.
    #
    # Yields each error to the provided block.
    #
    # Returns Enumerator object.
    def each(&block)
      @errors.each(&block)
    end
  end
end
