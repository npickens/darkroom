# frozen_string_literal: true

class Darkroom
  ##
  # Error class used when a spec is not defined for a particular file extension.
  #
  class SpecNotDefinedError < StandardError
    attr_reader(:extension, :file)

    ##
    # Creates a new instance.
    #
    # * +extension+ - Extension for which there is no spec defined.
    # * +file+ - File path of the asset whose loading was attempted.
    #
    def initialize(extension, file = nil)
      @extension = extension
      @file = file
    end

    ##
    # Returns a string representation of the error.
    #
    def to_s
      "Spec not defined for #{@extension} files#{" (#{@file})" if @file}"
    end
  end
end
