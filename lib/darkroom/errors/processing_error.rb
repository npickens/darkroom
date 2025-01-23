# frozen_string_literal: true

class Darkroom
  ##
  # Error class used to wrap all accumulated errors encountered during asset processing.
  #
  class ProcessingError < StandardError
    ##
    # Creates a new instance.
    #
    # [errors] Error or array of errors.
    #
    def initialize(errors)
      @errors = Array(errors).freeze

      super("Errors were encountered while processing assets:\n  #{@errors.map(&:to_s).join("\n  ")}")
    end

    ##
    # Yield each error to a block.
    #
    # [&block] Block to call and pass each error to.
    #
    def each(&block)
      @errors.each(&block)
    end
  end
end
