class Darkroom
  ##
  # Holds asset type-specific information and functionality.
  #
  # [minify_lib:] Name of a library to +require+ that is needed by the +minify+ lambda (optional).
  # [minify:] Lambda to call that will return the minified version of the asset's content (optional). One
  #           argument is passed when called:
  #           * +content+ - Content to minify.
  #
  class Delegate
    [
      :content_type, :parsers, :compile_lib, :compile_delegate, :compile_handler, :finalize_lib,
      :finalize_handler, :minify_lib, :minify_handler
    ].each do |name|
      var = :"@#{name}"
      instance_variable_set(var, nil)

      define_singleton_method(name) do
        instance_variable_defined?(var) ? instance_variable_get(var) : superclass.send(name)
      end
    end

    class << self; alias :get_content_type :content_type end

    ##
    # Sets or returns HTTP MIME type string.
    #
    def self.content_type(content_type = (get = true; nil))
      get ? get_content_type : (@content_type = content_type)
    end

    ##
    # Configures how imports are handled.
    #
    # [regex] Regex for finding import statements. Must contain a named component called +path+ (e.g.
    #         <tt>/^import (?<path>.*)/</tt>).
    # [&handler] Block for special handling of import statements (optional). Should
    #            <tt>throw(:error, '...')</tt> on error. Passed three arguments:
    #            * +parse_data:+ - Hash for storing data across calls to this and other parse handlers.
    #            * +match:+ - MatchData object from the match against +regex+.
    #            * +asset:+ - Asset object of the asset being imported.
    #            Return value is used as the substitution for the import statement, with optional second and
    #            third values as integers representing the start and end indexes of the match to replace.
    #
    def self.import(regex, &handler)
      parse(:import, regex, &handler)
    end

    ##
    # Configures how references are handled.
    #
    # [regex] Regex for finding references. Must contain three named components:
    #         * +path+ - Path of the asset being referenced.
    #         * +entity+ - Desired entity ('path' or 'content').
    #         * +format+ - Format to use (see Asset::REFERENCE_FORMATS).
    # [&handler] Block for special handling of references (optional). Should <tt>throw(:error, '...')</tt>
    #            on error. Passed four arguments:
    #            * +parse_data:+ - Hash for storing data across calls to this and other parse handlers.
    #            * +match:+ - MatchData object from the match against +regex+.
    #            * +asset:+ - Asset object of the asset being referenced.
    #            * +format:+ - Format of the reference (see Asset::REFERENCE_FORMATS).
    #            Return value is used as the substitution for the reference, with optional second and third
    #            values as integers representing the start and end indexes of the match to replace.
    #
    def self.reference(regex, &handler)
      parse(:reference, regex, &handler)
    end

    ##
    # Configures a parser.
    #
    # [kind] A name to describe what is being parsed. Should be unique across all +parse+ calls. When
    #        subclassing another Delegate, can be used to override the parent class's regex and handler.
    # [regex] Regex to match against.
    # [&handler] Block for handling matches of the regex. Should <tt>throw(:error, '...')</tt>
    #            on error. Passed two arguments:
    #            * +parse_data:+ - Hash for storing data across calls to this and other parse handlers.
    #            * +match:+ - MatchData object from the match against +regex+.
    #            Return value is used as the substitution for the reference, with optional second and third
    #            values as integers representing the start and end indexes of the match to replace.
    #
    def self.parse(kind, regex, &handler)
      @parsers = parsers&.dup || {} unless @parsers
      @parsers[kind] = [regex, handler]
    end

    ##
    # Configures compilation.
    #
    # [lib:] Name of a library to +require+ that is needed by the handler (optional).
    # [delegate:] Another Delegate to be used after the asset is compiled (optional).
    # [&handler] Block to call that will return the compiled version of the asset's own content. Passed
    #            three arguments when called:
    #.           * +parse_data:+ - Hash of data collected during parsing.
    #            * +path:+ - Path of the asset being compiled.
    #            * +own_content:+ - Asset's own content.
    #            Asset's own content is set to the value returned.
    #
    def self.compile(lib: nil, delegate: nil, &handler)
      @compile_lib = lib
      @compile_delegate = delegate
      @compile_handler = handler
    end

    ##
    # Configures finalize behavior.
    #
    # [lib:] Name of a library to +require+ that is needed by the handler (optional).
    # [&handler] Block to call that will return the completed version of the asset's overall content. Passed
    #            three arguments when called:
    #.           * +parse_data:+ - Hash of data collected during parsing.
    #            * +path:+ - Path of the asset being finalized.
    #            * +content:+ - Asset's content (with imports prepended).
    #            Asset's content is set to the value returned.
    #
    def self.finalize(lib: nil, &handler)
      @finalize_lib = lib
      @finalize_handler = handler
    end

    ##
    # Configures minification.
    #
    # [lib:] Name of a library to +require+ that is needed by the handler (optional).
    # [&handler] Block to call that will return the minified version of the asset's overall content. Passed
    #            three arguments when called:
    #.           * +parse_data:+ - Hash of data collected during parsing.
    #            * +path+ - Path of the asset being finalized.
    #            * +content+ - Finalized asset's content.
    #            Asset's minified content is set to the value returned.
    #
    def self.minify(lib: nil, &handler)
      @minify_lib = lib
      @minify_handler = handler
    end

    ##
    # Throws +:error+ with a message.
    #
    # [message] Message to include with the throw.
    #
    def self.error(message)
      throw(:error, message)
    end

    ##
    # Returns regex for a parser.
    #
    # [kind] Name of the parser.
    #
    def self.regex(kind)
      parsers[kind]&.first
    end

    ##
    # Returns handler for a parser.
    #
    # [kind] Name of the parser.
    #
    def self.handler(kind)
      parsers[kind]&.last
    end

    ##
    # Iterates over each parser and yields its kind, regex, and handler.
    #
    def self.each_parser
      parsers&.each do |kind, (regex, handler)|
        yield(kind, regex, handler)
      end
    end

    ##
    # DEPRECATED: subclass Delegate and use its DSL instead. Returns a subclass of Delegate configured using
    # the supplied Hash.
    #
    def self.new(**params)
      Darkroom.deprecated("#{self.name}::new is deprecated: use the DSL inside a child class or a block "\
        'passed to Darkroom.register')

      deprecated_from_hash(**params)
    end

    ##
    # DEPRECATED: subclass Delegate and use its DSL instead. Returns a subclass of Delegate configured using
    # the supplied Hash.
    #
    def self.deprecated_from_hash(content_type:, import_regex: nil, reference_regex: nil,
        validate_reference: nil, reference_content: nil, compile_lib: nil, compile: nil, compiled: nil,
        minify_lib: nil, minify: nil)
      Class.new(Delegate) do
        self.content_type(content_type)

        @import_regex = import_regex
        @reference_regex = reference_regex

        self.import(import_regex) if import_regex

        if validate_reference || reference_content
          @validate_reference = validate_reference
          @reference_content = reference_content

          self.reference(reference_regex) do |parse_data:, match:, asset:, format:|
            error_message = validate_reference&.call(asset, match, format)
            error(error_message) if error_message

            reference_content&.call(asset, match, format)
          end
        elsif reference_regex
          self.reference(reference_regex)
        end

        if compile
          self.compile(lib: compile_lib, delegate: compiled) do |parse_data:, path:, own_content:|
            compile.call(path, own_content)
          end
        elsif compile_lib || compiled
          self.compile(lib: compile_lib, delegate: compiled)
        end

        if minify
          self.minify(lib: minify_lib) do |parse_data:, path:, content:|
            minify.call(content)
          end
        end
      end
    end

    ##
    # DEPRECATED: subclass Delegate and use its DSL instead.
    #
    def self.import_regex() @import_regex end
    def self.reference_regex() @reference_regex end
    def self.validate_reference() @validate_reference end
    def self.reference_content() @reference_content end
  end
end
