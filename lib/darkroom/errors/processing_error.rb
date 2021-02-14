# frozen_string_literal: true

class Darkroom
  ##
  # Error class used to wrap all accumulated errors encountered during asset processing.
  #
  class ProcessingError < StandardError
    ##
    # Creates a new instance.
    #
    # * +errors+ - Error or array of errors.
    #
    def initialize(errors)
      @errors = Array(errors)
    end

    ##
    # Returns a string representation of the error.
    #
    def to_s
      "Errors were encountered while processing assets:\n  #{@errors.map(&:to_s).join("\n  ")}"
    end

    ##
    # Passes any missing method call on to the @errors array.
    #
    def method_missing(m, *args, &block)
      @errors.send(m, *args, &block)
    end
  end
end
