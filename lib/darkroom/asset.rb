# frozen_string_literal: true

require('base64')
require('digest')
require('set')

require_relative('darkroom')
require_relative('errors/asset_error')
require_relative('errors/asset_not_found_error')
require_relative('errors/circular_reference_error')
require_relative('errors/missing_library_error')
require_relative('errors/processing_error')
require_relative('errors/unrecognized_extension_error')

class Darkroom
  ##
  # Represents an asset.
  #
  class Asset
    EXTENSION_REGEX = /(?=\.\w+)/.freeze

    IMPORT_JOINER = "\n"
    DEFAULT_QUOTE = '\''

    QUOTED_PATH = /(?<quote>['"])(?<path>[^'"]*)\k<quote>/.freeze
    REFERENCE_PATH =
      %r{
        (?<quote>['"]?)(?<quoted>
          (?<path>[^#{DISALLOWED_PATH_CHARS}]+)
          \?asset-(?<entity>path|content)(=(?<format>\w*))?
        )\k<quote>
      }x.freeze

    # First item of each set is used as default, so order is important.
    REFERENCE_FORMATS = {
      'path' => Set.new(%w[versioned unversioned]),
      'content' => Set.new(%w[base64 utf8 displace]),
    }.freeze

    @@delegates = {}
    @@glob = ''

    attr_reader(:content, :error, :errors, :path, :path_unversioned, :path_versioned)

    ##
    # Holds information about how to handle a particular asset type.
    #
    # * +content_type+ - HTTP MIME type string.
    # * +import_regex+ - Regex to find import statements. Must contain a named component called 'path'
    #   (e.g. +/^import (?<path>.*)/+).
    # * +reference_regex+ - Regex to find references to other assets. Must contain three named components:
    #   * +path+ - Path of the asset being referenced.
    #   * +entity+ - Desired entity (path or content).
    #   * +format+ - Format to use (see REFERENCE_FORMATS).
    # * +validate_reference+ - Lambda to call to validate a reference. Should return nil if there are no
    #   errors and a string error message if validation fails. Three arguments are passed when called:
    #   * +asset+ - Asset object of the asset being referenced.
    #   * +match+ - MatchData object from the match against +reference_regex+.
    #   * +format+ - Format of the reference (see REFERENCE_FORMATS).
    # * +reference_content+ - Lambda to call to get the content for a reference. Should return nil if the
    #   default behavior is desired or a string for custom content. Three arguments are passed when called:
    #   * +asset+ - Asset object of the asset being referenced.
    #   * +match+ - MatchData object from the match against +reference_regex+.
    #   * +format+ - Format of the reference (see REFERENCE_FORMATS).
    # * +compile_lib+ - Name of a library to +require+ that is needed by the +compile+ lambda.
    # * +compile+ - Lambda to call that will return the compiled version of the asset's content. Two
    #   arguments are passed when called:
    #   * +path+ - Path of the asset being compiled.
    #   * +content+ - Content to compile.
    # * +minify_lib+ - Name of a library to +require+ that is needed by the +minify+ lambda.
    # * +minify+ - Lambda to call that will return the minified version of the asset's content. One argument
    #   is passed when called:
    #   * +content+ - Content to minify.
    #
    Delegate = Struct.new(:content_type, :import_regex, :reference_regex, :validate_reference,
      :reference_content, :compile_lib, :compile, :minify_lib, :minify, keyword_init: true)

    ##
    # Registers a delegate.
    #
    # * +delegate+ - An HTTP MIME type string, a Hash of Delegate parameters, or a Delegate instance.
    # * +extensions+ - File extension(s) to associate with this delegate.
    #
    def self.register(*extensions, delegate)
      case delegate
      when String
        delegate = Delegate.new(content_type: delegate.freeze)
      when Hash
        delegate = Delegate.new(**delegate)
      end

      extensions.each do |extension|
        @@delegates[extension] = delegate
      end

      @@glob = "**/*{#{@@delegates.keys.sort.join(',')}}"

      delegate
    end

    ##
    # Returns glob for files of all registered delegates.
    #
    def self.glob
      @@glob
    end

    ##
    # Creates a new instance.
    #
    # * +file+ - Path of file on disk.
    # * +path+ - Path this asset will be referenced by (e.g. /js/app.js).
    # * +darkroom+ - Darkroom instance that the asset is a member of.
    # * +prefix+ - Prefix to apply to unversioned and versioned paths.
    # * +minify+ - Boolean specifying whether or not the asset should be minified when processed.
    # * +internal+ - Boolean indicating whether or not the asset is only accessible internally (i.e. as an
    #   import or reference).
    #
    def initialize(path, file, darkroom, prefix: nil, minify: false, internal: false)
      @path = path
      @file = file
      @darkroom = darkroom
      @prefix = prefix
      @minify = minify
      @internal = internal

      @path_unversioned = "#{@prefix}#{@path}"
      @extension = File.extname(@path).downcase
      @delegate = @@delegates[@extension] or raise(UnrecognizedExtensionError.new(@path))

      require_libs
      clear
    end

    ##
    # Processes the asset if modified (see #modified? for how modification is determined). File is read from
    # disk, references are substituted (if supported), content is compiled (if required), imports are
    # prefixed to its content (if supported), and content is minified (if supported and enabled). Returns
    # true if asset was modified since it was last processed and false otherwise.
    #
    def process
      @process_key == @darkroom.process_key ? (return @processed) : (@process_key = @darkroom.process_key)
      modified? ? (@processed = true) : (return @processed = false)

      clear
      read
      build_imports
      build_references
      process_dependencies
      compile
      minify

      @fingerprint = Digest::MD5.hexdigest(@content)
      @path_versioned = "#{@prefix}#{@path.sub(EXTENSION_REGEX, "-#{@fingerprint}")}"

      @processed
    rescue Errno::ENOENT
      # File was deleted. Do nothing.
    ensure
      @error = @errors.empty? ? nil : ProcessingError.new(@errors)
    end

    ##
    # Returns the HTTP MIME type string.
    #
    def content_type
      @delegate.content_type
    end

    ##
    # Returns boolean indicating whether or not the asset is binary.
    #
    def binary?
      return @is_binary if defined?(@is_binary)

      type, subtype = content_type.split('/')

      @is_binary = type != 'text' && !subtype.include?('json') && !subtype.include?('xml')
    end

    ##
    # Returns boolean indicating whether or not the asset is a font.
    #
    def font?
      defined?(@is_font) ? @is_font : (@is_font = content_type.start_with?('font/'))
    end

    ##
    # Returns boolean indicating whether or not the asset is an image.
    #
    def image?
      defined?(@is_image) ? @is_image : (@is_image = content_type.start_with?('image/'))
    end

    ##
    # Returns appropriate HTTP headers.
    #
    # * +versioned+ - Uses Cache-Control header with max-age if +true+ and ETag header if +false+.
    #
    def headers(versioned: true)
      {
        'Content-Type' => content_type,
        'Cache-Control' => ('public, max-age=31536000' if versioned),
        'ETag' => ("\"#{@fingerprint}\"" if !versioned),
      }.compact!
    end

    ##
    # Returns subresource integrity string.
    #
    # * +algorithm+ - Hash algorithm to use to generate the integrity string (one of :sha256, :sha384, or
    #   :sha512).
    #
    def integrity(algorithm = :sha384)
      @integrity[algorithm] ||= "#{algorithm}-#{Base64.strict_encode64(
        case algorithm
        when :sha256 then Digest::SHA256.digest(@content)
        when :sha384 then Digest::SHA384.digest(@content)
        when :sha512 then Digest::SHA512.digest(@content)
        else raise("Unrecognized integrity algorithm: #{algorithm}")
        end
      )}".freeze
    end

    ##
    # Returns boolean indicating whether or not the asset is marked as internal.
    #
    def internal?
      @internal
    end

    ##
    # Returns boolean indicating whether or not an error was encountered the last time the asset was
    # processed.
    #
    def error?
      !!@error
    end

    ##
    # Returns high-level object info string.
    #
    def inspect
      "#<#{self.class}: "\
        "@errors=#{@errors.inspect}, "\
        "@extension=#{@extension.inspect}, "\
        "@file=#{@file.inspect}, "\
        "@fingerprint=#{@fingerprint.inspect}, "\
        "@internal=#{@internal.inspect}, "\
        "@minify=#{@minify.inspect}, "\
        "@mtime=#{@mtime.inspect}, "\
        "@path=#{@path.inspect}, "\
        "@path_unversioned=#{@path_unversioned.inspect}, "\
        "@path_versioned=#{@path_versioned.inspect}, "\
        "@prefix=#{@prefix.inspect}"\
      '>'
    end

    protected

    ##
    # Returns true if the asset or any of its dependencies were modified since last processed, or if an
    # error was recorded during the last processing run.
    #
    def modified?
      @modified_key == @darkroom.process_key ? (return @modified) : (@modified_key = @darkroom.process_key)

      begin
        @modified = !!@error
        @modified ||= @mtime != (@mtime = File.mtime(@file))
        @modified ||= dependencies.any? { |d| d.modified? }
      rescue Errno::ENOENT
        @modified = true
      end
    end

    ##
    # Returns all dependencies (including dependencies of dependencies).
    #
    # * +ignore+ - Assets already accounted for as dependency tree is walked (to prevent infinite loops when
    #   circular chains are encountered).
    #
    def dependencies(ignore = nil)
      return @dependencies if @dependencies

      dependencies = accumulate(:dependencies, ignore)
      @dependencies = dependencies unless ignore

      dependencies
    end

    ##
    # Returns all imports (including imports of imports).
    #
    # * +ignore+ - Assets already accounted for as import tree is walked (to prevent infinite loops when
    #   circular chains are encountered).
    #
    def imports(ignore = nil)
      return @imports if @imports

      imports = accumulate(:imports, ignore)
      @imports = imports unless ignore

      imports
    end

    ##
    # Returns the processed content of the asset without dependencies concatenated.
    #
    def own_content
      @own_content
    end

    private

    ##
    # Clears content, dependencies, and errors so asset is ready for (re)processing.
    #
    def clear
      @dependencies = nil
      @imports = nil
      @error = nil
      @fingerprint = nil
      @path_versioned = nil

      (@own_dependencies ||= []).clear
      (@own_imports ||= []).clear
      (@dependency_matches ||= []).clear
      (@errors ||= []).clear
      (@content ||= +'').clear
      (@own_content ||= +'').clear
      (@integrity ||= {}).clear
    end

    ##
    # Reads the asset file into memory.
    #
    def read
      @own_content = File.read(@file)
    end

    ##
    # Builds reference info.
    #
    def build_references
      return unless @delegate.reference_regex

      @own_content.scan(@delegate.reference_regex) do
        match = Regexp.last_match
        path = match[:path]
        format = match[:format]
        format = REFERENCE_FORMATS[match[:entity]].first if format.nil? || format == ''

        if (asset = @darkroom.manifest(path))
          if !REFERENCE_FORMATS[match[:entity]].include?(format)
            @errors << AssetError.new("Invalid reference format '#{format}' (must be one of "\
              "'#{REFERENCE_FORMATS[match[:entity]].join("', '")}')", match[0], @path, line_num(match))
          elsif match[:entity] == 'content' && format != 'base64' && asset.binary?
            @errors << AssetError.new('Base64 encoding is required for binary assets', match[0], @path,
              line_num(match))
          elsif (error = @delegate.validate_reference&.(asset, match, format))
            @errors << AssetError.new(error, match[0], @path, line_num(match))
          else
            @own_dependencies << asset
            @dependency_matches << [:reference, asset, match, format]
          end
        else
          @errors << not_found_error(path, match)
        end
      end
    end

    ##
    # Builds import info.
    #
    def build_imports
      return unless @delegate.import_regex

      @own_content.scan(@delegate.import_regex) do
        match = Regexp.last_match
        path = match[:path]

        if (asset = @darkroom.manifest(path))
          @own_dependencies << asset
          @own_imports << asset
          @dependency_matches << [:import, asset, match]
        else
          @errors << not_found_error(path, match)
        end
      end
    end

    ##
    # Processes imports and references.
    #
    def process_dependencies
      @dependency_matches.sort_by! { |_, __, match| -match.begin(0) }.each do |kind, asset, match, format|
        if kind == :import
          @own_content[match.begin(0)...match.end(0)] = ''
        elsif asset.dependencies.include?(self)
          @errors << CircularReferenceError.new(match[0], @path, line_num(match))
        else
          value, start, finish = @delegate.reference_content&.(asset, match, format)
          min_start, max_finish = match.offset(0)
          start ||= format == 'displace' ? min_start : match.begin(:quoted)
          finish ||= format == 'displace' ? max_finish : match.end(:quoted)
          start = [[start, min_start].max, max_finish].min
          finish = [[finish, max_finish].min, min_start].max

          @own_content[start...finish] =
            case "#{match[:entity]}-#{format}"
            when 'path-versioned'
              value || asset.path_versioned
            when 'path-unversioned'
              value || asset.path_unversioned
            when 'content-base64'
              quote = DEFAULT_QUOTE if match[:quote] == ''
              data = Base64.strict_encode64(value || asset.content)
              "#{quote}data:#{asset.content_type};base64,#{data}#{quote}"
            when 'content-utf8'
              quote = DEFAULT_QUOTE if match[:quote] == ''
              "#{quote}data:#{asset.content_type};utf8,#{value || asset.content}#{quote}"
            when 'content-displace'
              value || asset.content
            end
        end
      end

      @content << imports.map { |d| d.own_content }.join(IMPORT_JOINER)
    end

    ##
    # Compiles the asset if compilation is supported for the asset's type and appends the asset's own
    # content to the overall content string.
    #
    def compile
      if @delegate.compile
        begin
          @own_content = @delegate.compile.(@path, @own_content)
        rescue => e
          @errors << e
        end
      end

      @content << @own_content
    end

    ##
    # Minifies the asset if minification is supported for the asset's type, asset is marked as minifiable
    # (i.e. it's not already minified), and the asset is not marked as internal-only.
    #
    def minify
      if @delegate.minify && @minify && !@internal
        begin
          @content = @delegate.minify.(@content)
        rescue => e
          @errors << e
        end
      end

      @content
    end

    ##
    # Requires any libraries necessary for compiling and minifying the asset based on its type. Raises a
    # MissingLibraryError if library cannot be loaded.
    #
    # Darkroom does not explicitly depend on any libraries necessary for asset compilation or minification,
    # since not every app will use every kind of asset or use minification. It is instead up to each app
    # using Darkroom to specify any needed compilation and minification libraries as direct dependencies
    # (e.g. specify +gem('terser')+ in the app's Gemfile if JavaScript minification is desired).
    #
    def require_libs
      begin
        require(@delegate.compile_lib) if @delegate.compile_lib
      rescue LoadError
        compile_load_error = true
      end

      begin
        require(@delegate.minify_lib) if @delegate.minify_lib && @minify
      rescue LoadError
        minify_load_error = true
      end

      raise(MissingLibraryError.new(@delegate.compile_lib, 'compile', @extension)) if compile_load_error
      raise(MissingLibraryError.new(@delegate.minify_lib, 'minify', @extension)) if minify_load_error
    end

    ##
    # Utility method used by #dependencies and #imports to recursively build arrays.
    #
    # * +name+ - Name of the array to accumulate (:dependencies or :imports).
    # * +ignore+ - Set of assets already accumulated which can be ignored (used to avoid infinite loops when
    #   circular references are encountered).
    #
    def accumulate(name, ignore)
      ignore ||= Set.new
      ignore << self

      process

      instance_variable_get(:"@own_#{name}").each_with_object([]) do |asset, assets|
        next if ignore.include?(asset)

        asset.process
        assets.push(*asset.send(name, ignore), asset)
        assets.uniq!
        assets.delete(self)
      end
    end

    ##
    # Utility method that returns the appropriate error for a dependency that doesn't exist.
    #
    # * +path+ - Path of the asset which cannot be found.
    # * +match+ - MatchData object of the regex for the asset that cannot be found.
    #
    def not_found_error(path, match)
      klass = @@delegates[File.extname(path)] ? AssetNotFoundError : UnrecognizedExtensionError
      klass.new(path, @path, line_num(match))
    end

    ##
    # Utility method that returns the line number where a regex match was found.
    #
    # * +match+ - MatchData object of the regex.
    #
    def line_num(match)
      @own_content[0..match.begin(:path)].count("\n") + 1
    end
  end
end
