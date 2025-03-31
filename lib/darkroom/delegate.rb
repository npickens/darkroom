# frozen_string_literal: true

class Darkroom
  # Holds asset type-specific information and functionality.
  class Delegate
    IMPORT_REGEX_CAPTURES = %w[path].freeze
    REFERENCE_REGEX_CAPTURES = %w[quote path quoted entity format].freeze
    LIB_REQUIRES = [:compile, :finalize, :minify].freeze

    @content_type = nil
    @parsers = nil
    @compile_lib = nil
    @compile_delegate = nil
    @compile_handler = nil
    @finalize_lib = nil
    @finalize_handler = nil
    @minify_lib = nil
    @minify_handler = nil

    # Public: Set and/or get the HTTP MIME type string, falling back to that of the parent class.
    #
    # Returns the String content type.
    def self.content_type(content_type = (get = true; nil))
      if get
        defined?(@content_type) ? @content_type : superclass.content_type
      else
        @content_type = content_type
      end
    end

    # Public: Get parsers, falling back to those of the parent class.
    #
    # Returns the Array of Proc parsers.
    def self.parsers
      defined?(@parsers) ? @parsers : superclass.parsers
    end

    # Public: Iterate over each parser.
    #
    # Yields each parser's Symbol kind, Regexp regex, and Proc handler.
    #
    # Returns nothing.
    def self.each_parser
      parsers&.each do |kind, (regex, handler)|
        yield(kind, regex, handler)
      end
    end

    # Public: Get the name of the compile library to require, falling back to that of the parent class.
    #
    # Returns the String library name if present or nil otherwise.
    def self.compile_lib
      defined?(@compile_lib) ? @compile_lib : superclass.compile_lib
    end

    # Public: Get the Delegate class used once an asset is compiled, falling back to that of the parent
    # class.
    #
    # Returns the Delegate class if present or nil otherwise.
    def self.compile_delegate
      defined?(@compile_delegate) ? @compile_delegate : superclass.compile_delegate
    end

    # Public: Get the compile handler, falling back to that of the parent class.
    #
    # Returns the Proc handler if present or nil otherwise.
    def self.compile_handler
      defined?(@compile_handler) ? @compile_handler : superclass.compile_handler
    end

    # Public: Get the name of the finalize library to require, falling back to that of the parent class.
    #
    # Returns the String library name if present or nil otherwise.
    def self.finalize_lib
      defined?(@finalize_lib) ? @finalize_lib : superclass.finalize_lib
    end

    # Public: Get the finalize handler, falling back to that of the parent class.
    #
    # Returns the Proc handler if present or nil otherwise.
    def self.finalize_handler
      defined?(@finalize_handler) ? @finalize_handler : superclass.finalize_handler
    end

    # Public: Get the name of the minify library to require, falling back to that of the parent class.
    #
    # Returns the String library name if present or nil otherwise.
    def self.minify_lib
      defined?(@minify_lib) ? @minify_lib : superclass.minify_lib
    end

    # Public: Get the minify handler, falling back to that of the parent class.
    #
    # Returns the Proc handler if present or nil otherwise.
    def self.minify_handler
      defined?(@minify_handler) ? @minify_handler : superclass.minify_handler
    end

    # Internal: Configure import handling.
    #
    # regex   - Regexp for finding import statements. Must contain a named components :quote (' or ") and
    #           :path (the path of the asset being imported).
    # handler - Proc for special handling of import statements (optional), which is passed three keyword
    #           arguments:
    #
    #           parse_data: - Hash for storing arbitrary data across calls to this and other handlers.
    #           match:      - MatchData object from the match against the regex.
    #           asset:      - Asset object of the asset being imported.
    #
    #           Returns nil for default behavior, or a String which is used as the substitution for the text
    #             matched by the regex. The portion of the matched text that is replaced can optionally be
    #             changed by returning second and third Integer values specifying start and end indexes
    #             within the regex match (e.g. ['my substitution', match.begin(:path) + 1,
    #             match.end(:path) - 1]).
    #           Throws :error with a String message when an error is encountered.
    #
    # Returns nothing.
    # Raises RuntimeError if the regex does not have the required named captures.
    def self.import(regex, &handler)
      validate_regex!(:import, regex, IMPORT_REGEX_CAPTURES)

      parse(:import, regex, &handler)
    end

    # Internal: Configure reference handling.
    #
    # regex -   Regex for finding references. Must contain named components :quote (' or "), :path (the path
    #           of the asset being referenced), :quoted (everything inside the quotes), :entity ('path' or
    #           'content'), and :format (see Asset::REFERENCE_FORMATS).
    # handler - Proc for special handling of references (optional), which is passed four keyword arguments:
    #
    #           parse_data: - Hash for storing arbitrary data across calls to this and other handlers.
    #           match:      - MatchData object from the match against the regex.
    #           asset:      - Asset object of the asset being referenced.
    #           format:     - String format of the reference (see Asset::REFERENCE_FORMATS).
    #
    #           Returns nil for default behavior, or a String which is used as the substitution for the text
    #             matched by the regex. The portion of the matched text that is replaced can optionally be
    #             changed by returning second and third Integer values specifying start and end indexes
    #             within the regex match (e.g. ['my substitution', match.begin(:path) + 1,
    #             match.end(:path) - 1]).
    #           Throws :error with a String message when an error is encountered.
    #
    # Returns nothing.
    # Raises RuntimeError if the regex does not have the required named captures.
    def self.reference(regex, &handler)
      validate_regex!(:reference, regex, REFERENCE_REGEX_CAPTURES)

      parse(:reference, regex, &handler)
    end

    # Internal: Configure a parser.
    #
    # kind    - Symbol name to describe what is being parsed. Should be unique across all parse calls. When
    #           subclassing another Delegate, this can be used to override the parent class's regex and
    #           handler.
    # regex   - Regexp to match against.
    # handler - Proc for handling matches of the regex, which is passed two keyword arguments:
    #
    #           parse_data: - Hash for storing arbitrary data across calls to this and other handlers.
    #           match:      - MatchData object from the match against the regex.
    #
    #           Returns a String which is used as the substitution for the text matched by the regex. The
    #             portion of the matched text that is replaced can optionally be changed by returning second
    #             and third Integer values specifying start and end indexes within the regex match (e.g.
    #             ['my substitution', match.begin(:path) + 1, match.end(:path) - 1]).
    #           Throws :error with a String message when an error is encountered.
    #
    # Returns nothing.
    def self.parse(kind, regex, &handler)
      @parsers ||= parsers&.dup || {}
      @parsers[kind] = [regex, handler]
    end

    # Internal: Configure compilation.
    #
    # lib:      - String name of a library to require that is needed by the handler (optional).
    # delegate: - Delegate class to be used after the asset is compiled (optional).
    # handler   - Proc to call that will return the compiled version of the asset's own content, which is
    #             passed three keyword arguments:
    #
    #             parse_data:  - Hash for storing arbitrary data across calls to this and other handlers.
    #             path:        - String path of the asset.
    #             own_content: - String own content (without imports) of the asset.
    #
    #             Returns a String which is used as a replacement for the asset's own content.
    #             Raises StandardError when an error is encountered.
    #
    # Returns nothing.
    def self.compile(lib: nil, delegate: nil, &handler)
      @compile_lib = lib
      @compile_delegate = delegate
      @compile_handler = handler
    end

    # Internal: Configure finalize behavior.
    #
    # lib:    - String name of a library to require that is needed by the handler (optional).
    # handler - Proc to call that will return the finalized version of the asset's compiled content (with
    #           imports prepended), which is passed three keyword arguments:
    #
    #           parse_data: - Hash for storing arbitrary data across calls to this and other handlers.
    #           path:       - String path of the asset.
    #           content:    - String content of the compiled asset (with imports prepended).
    #
    #           Returns a String which is used as a replacement for the asset's content.
    #           Raises StandardError when an error is encountered.
    #
    # Returns nothing.
    def self.finalize(lib: nil, &handler)
      @finalize_lib = lib
      @finalize_handler = handler
    end

    # Internal: Configure minification.
    #
    # lib:    - String name of a library to require that is needed by the handler (optional).
    # handler - Proc to call that will return the minified version of the asset's finalized content, which
    #           is passed three keyword arguments:
    #
    #           parse_data: - Hash for storing arbitrary data across calls to this and other handlers.
    #           path:       - String oath of the asset being minified.
    #           content:    - String content of the finalized asset.
    #
    #           Returns a String which is used as the minified version of the asset's content.
    #           Raises StandardError when an error is encountered.
    #
    def self.minify(lib: nil, &handler)
      @minify_lib = lib
      @minify_handler = handler
    end

    # Internal: Throw :error with a message.
    #
    # message - String message to include with the throw.
    #
    # Returns nothing.
    def self.error(message)
      throw(:error, message)
    end

    # Internal: Get a parser's regex.
    #
    # kind - Symbol name of the parser.
    #
    # Returns the Regexp.
    def self.regex(kind)
      parsers[kind]&.first
    end

    # Internal: Get a parser's handler.
    #
    # kind - Symbol name of the parser.
    #
    # Returns the Proc handler.
    def self.handler(kind)
      parsers[kind]&.last
    end

    # Internal: Raise an exception if a regex does not have the required named captures.
    #
    # name              - Symbol name of the regex (used in the exception message).
    # regex             - Regexp to validate.
    # required_captures - Array of String required named captures.
    #
    # Returns nothing.
    # Raises RuntimeError if the regex does not have the required named captures.
    def self.validate_regex!(name, regex, required_captures)
      missing = (required_captures - regex.named_captures.keys)

      return if missing.empty?

      name = name.to_s.capitalize
      plural = missing.size != 1
      missing_str = missing.join(', ')

      raise("#{name} regex is missing required named capture#{'s' if plural}: #{missing_str}")
    end
  end
end
