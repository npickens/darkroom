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

    # Public: When a block is given, iterate over the errors array, passing each error to the block. When a
    # block is not given, return a new Enumerator.
    #
    # block - Block to call and pass each error to.
    #
    # Yields each error to the provided block.
    #
    # Returns the errors Array if a block is given or a new Enumerator if no block is given.
    def each(&block)
      block ? @errors.each(&block) : to_enum(:each)
    end
  end
end
