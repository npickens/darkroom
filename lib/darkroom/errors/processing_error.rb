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
      @errors = Array(errors).sort_by { |e| e.respond_to?(:path) ? e.path : '' }
    end

    ##
    # Iterates over each error.
    #
    # * +&block+ - Block to execute for each error.
    #
    def each(&block)
      @errors.each(&block)
    end

    ##
    # Returns a string representation of the error.
    #
    def to_s
      if @errors.size == 1
        @errors.first.message
      else
        "Errors were encountered while processing assets:\n  #{@errors.map(&:message).join("\n  ")}"
      end
    end
  end
end
