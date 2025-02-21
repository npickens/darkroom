# frozen_string_literal: true

require('base64')
require('digest')
require('set')

require_relative('delegate')
require_relative('errors/asset_error')
require_relative('errors/asset_not_found_error')
require_relative('errors/circular_reference_error')
require_relative('errors/missing_library_error')
require_relative('errors/processing_error')
require_relative('errors/unrecognized_extension_error')

class Darkroom
  # Represents an asset.
  class Asset
    EXTENSION_REGEX = /(?=\.\w+)/
    DEFAULT_QUOTE = '\''
    DISALLOWED_PATH_CHARS = '\'"`=<>? '
    INVALID_PATH_REGEX = /[#{DISALLOWED_PATH_CHARS}]/
    PATH_REGEX = /(?<path>[^#{DISALLOWED_PATH_CHARS}]*)/
    QUOTED_PATH_REGEX = /(?<quote>['"])#{PATH_REGEX.source}\k<quote>/
    REFERENCE_REGEX = /
      (?<quote>['"]?)
        (?<quoted>#{PATH_REGEX.source}\?asset-(?<entity>path|content)(=(?<format>\w*))?)
      \k<quote>
    /x

    BUILT_IN_PARSE_KINDS = [:import, :reference].freeze

    # First item of each set is used as default, so order is important.
    REFERENCE_FORMATS = {
      'path' => Set.new(%w[versioned unversioned]),
      'content' => Set.new(%w[base64 utf8 displace]),
    }.freeze

    attr_reader(:errors, :path, :path_unversioned)

    # Public: Create a new instance.
    #
    # path          - String path this asset will be referenced by (e.g. /js/app.js).
    # file          - String absolute path of file on disk.
    # darkroom      - Darkroom instance that the asset is a member of.
    # prefix:       - String prefix to apply to unversioned and versioned paths.
    # entry:        - Boolean specifying if the asset is an entry point (i.e. accessible externally).
    # minify:       - Boolean specifying if the asset should be minified when processed.
    # intermediate: - Boolean specifying if the asset exists solely to provide an intermediate form (e.g.
    #                 compiled) for another Asset instance.
    def initialize(path, file, darkroom, prefix: nil, entry: true, minify: false, intermediate: false)
      @path = path
      @dir = File.dirname(path)
      @file = file
      @darkroom = darkroom
      @prefix = prefix
      @entry = entry
      @minify = minify

      @path_unversioned = "#{@prefix}#{@path}"
      @extension = File.extname(@path).downcase
      @delegate = Darkroom.delegate(@extension) or raise(UnrecognizedExtensionError.new(@path))

      @ran = Set.new

      if @delegate.compile_delegate && !intermediate
        @delegate = @delegate.compile_delegate
        @intermediate_asset = Asset.new(
          @path, @file, @darkroom,
          prefix: @prefix,
          entry: false,
          minify: false,
          intermediate: true,
        )
      end

      require_libs
      clear
    end

    # Public: Process the asset if it's been modified since the last run (see #modified? for how
    # modification is determined). The asset file is read from disk, references are substituted (if
    # supported for the asset type), content is compiled (if required), imports are prefixed to the asset's
    # own content (if supported), and content is minified (if supported and enabled and the asset is an
    # entry point).
    #
    # Returns nothing.
    def process
      return if ran?(:process)

      compile
      content if entry?
    end

    # Public: Get the HTTP MIME type string for this asset.
    #
    # Returns the String content type from the asset's Delegate.
    def content_type
      @delegate.content_type
    end

    # Public: Check if the asset's content is binary.
    #
    # Returns the boolean result.
    def binary?
      return @binary if defined?(@binary)

      type, subtype = content_type.split('/')

      @binary = type != 'text' && !subtype.include?('json') && !subtype.include?('xml')
    end

    # Public: Check if the asset is a font.
    #
    # Returns the boolean result.
    def font?
      defined?(@is_font) ? @is_font : (@is_font = content_type.start_with?('font/'))
    end

    # Public: Check if the asset is an image.
    #
    # Returns the boolean result.
    def image?
      defined?(@is_image) ? @is_image : (@is_image = content_type.start_with?('image/'))
    end

    # Public: Check if the asset is an entry point.
    #
    # Returns the boolean result.
    def entry?
      @entry
    end

    # Public: Check if one or more errors were encountered the last time the asset was processed.
    #
    # Returns the boolean result.
    def error?
      @errors && !@errors.empty?
    end

    # Public: Get a single error wrapper object for all errors.
    #
    # Returns a ProcessingError if one or more errors exit or nil otherwise.
    def error
      @error ||= error? ? ProcessingError.new(@errors) : nil
    end

    # Public: Get an MD5 hash of the asset's content.
    #
    # Returns the String hash.
    def fingerprint
      content

      @fingerprint
    end

    # Public: Get the versioned path of the asset (includes the fingerprint).
    #
    # Returns the String versioned path.
    def path_versioned
      content

      @path_versioned
    end

    # Public: Get the asset's HTTP headers.
    #
    # versioned: - Boolean indicating if this is for the versioned or unversioned asset path. If true,
    #              a Cache-Control header with max-age is included; if false, an ETag header is used.
    #
    # Returns a Hash of String HTTP header names and String values.
    def headers(versioned: true)
      @headers[versioned] ||=
        {'Content-Type' => content_type}.merge!(
          if versioned
            {'Cache-Control' => 'public, max-age=31536000'}
          else
            {'ETag' => %("#{fingerprint}")}
          end
        )
    end

    # Public: Get a subresource integrity string (SHA digest).
    #
    # algorithm - Symbol hash algorithm name to use to generate the integrity string (must be one of
    #             :sha256, :sha384, :sha512).
    #
    # Returns the String SHA digest.
    # Raises RuntimeError if the request algorithm is not valid.
    def integrity(algorithm = :sha384)
      @integrity[algorithm] ||= "#{algorithm}-#{Base64.strict_encode64(
        case algorithm
        when :sha256 then Digest::SHA256.digest(content)
        when :sha384 then Digest::SHA384.digest(content)
        when :sha512 then Digest::SHA512.digest(content)
        else raise("Unrecognized integrity algorithm: #{algorithm}")
        end
      )}".freeze
    end

    # Public: Get the full asset content, including imports and asset reference content substitutions.
    #
    # minified: - Boolean specifying if the minified version is desired.
    #
    # Returns the String asset content, minified if requested (and the asset is minifiable).
    def content(minified: @minify)
      unless ran?(:content)
        compile

        @content =
          if imports.empty?
            @own_content
          else
            (0..imports.size).inject(+'') do |content, i|
              own_content = (imports[i] || self).own_content

              content << "\n" unless (content[-1] == "\n" && own_content[0] == "\n") || content.empty?
              content << own_content
            end
          end

        begin
          finalized = @delegate.finalize_handler&.call(
            parse_data: @parse_data,
            path: @path,
            content: @content,
          )

          @content = finalized if finalized.kind_of?(String)
        rescue StandardError => e
          @errors << e
        end
      end

      if @delegate.minify_handler && !@content_minified && (minified || @minify)
        begin
          @content_minified = @delegate.minify_handler.call(
            parse_data: @parse_data,
            path: @path,
            content: @content,
          )
        rescue StandardError => e
          @errors << e
        end
      end

      @fingerprint ||= Digest::MD5.hexdigest((@minify && @content_minified) || @content).freeze
      @path_versioned ||= "#{@prefix}#{@path.sub(EXTENSION_REGEX, "-#{@fingerprint}")}"

      (minified && @content_minified) || @content
    ensure
      @content.freeze
      @content_minified.freeze
    end

    # Public: Get a high-level object info string about this Asset instance.
    #
    # Returns the String.
    def inspect
      "#<#{self.class} " \
        "@delegate=#{@delegate.inspect}, " \
        "@dir=#{@dir.inspect}, " \
        "@entry=#{@entry.inspect}, " \
        "@errors=#{@errors.inspect}, " \
        "@extension=#{@extension.inspect}, " \
        "@file=#{@file.inspect}, " \
        "@fingerprint=#{@fingerprint.inspect}, " \
        "@minify=#{@minify.inspect}, " \
        "@modified=#{@modified.inspect}, " \
        "@mtime=#{@mtime.inspect}, " \
        "@path=#{@path.inspect}, " \
        "@path_unversioned=#{@path_unversioned.inspect}, " \
        "@path_versioned=#{@path_versioned.inspect}, " \
        "@prefix=#{@prefix.inspect}" \
      '>'
    end

    protected

    # Internal: Check if the asset or any of its dependencies were modified since last processed, or if an
    # error was recorded during the last processing run.
    #
    # Returns the boolean result.
    def modified?
      @modified_key == @darkroom.process_key ? (return @modified) : @modified_key = @darkroom.process_key

      begin
        @modified = error?
        @modified ||= (@mtime != (@mtime = File.mtime(@file)))
        @modified ||= @intermediate_asset.modified? if @intermediate_asset
        @modified ||= dependencies.any? { |d| d.modified? }

        @ran.clear if @modified

        @modified
      rescue Errno::ENOENT
        @modified = true
      end
    end

    # Internal: Clear content, dependencies, and errors so asset is ready for (re)processing.
    #
    # Returns nothing.
    def clear
      return if ran?(:clear)

      @own_dependencies = []
      @own_imports = []
      @parse_matches = []
      @parse_data = {}

      @dependencies = nil
      @imports = nil

      @own_content = nil
      @content = nil
      @content_minified = nil

      @fingerprint = nil
      @path_versioned = nil
      @headers = {}
      @integrity = {}

      @error = nil
      @errors = []
    end

    # Internal: Read the asset file into memory.
    #
    # Returns nothing.
    def read
      return if ran?(:read)

      clear

      if @intermediate_asset
        @own_content = @intermediate_asset.own_content.dup
        @errors.concat(@intermediate_asset.errors)
      else
        begin
          @own_content = File.read(@file)
        rescue Errno::ENOENT
          # Gracefully handle file deletion.
          @own_content = ''
        end
      end
    end

    # Internal: Parse the asset's own content to build the lists of imports and references.
    #
    # Returns nothing.
    def parse
      return if ran?(:parse)

      read

      @delegate.each_parser do |kind, regex, _|
        @own_content.scan(regex) do
          match = Regexp.last_match
          asset = nil

          if BUILT_IN_PARSE_KINDS.include?(kind)
            path = File.expand_path(match[:path], @dir)
            asset = @darkroom.manifest(path)

            @own_dependencies << asset if asset
            @own_imports << asset if asset && kind == :import
          end

          @parse_matches << [kind, match, asset]
        end
      end
    end

    # Internal: Get direct dependencies (ones explicitly specified in the asset's own content).
    #
    # Returns an Array of Asset objects.
    def own_dependencies
      parse

      @own_dependencies
    end

    # Internal: Get all dependencies (including dependencies of dependencies).
    #
    # Returns an Array of Asset objects.
    def dependencies
      unless ran?(:dependencies)
        parse
        @dependencies = accumulate(:own_dependencies)
      end

      @dependencies
    end

    # Internal: Get direct imports (ones explicitly specified in the asset's own content).
    #
    # Returns an Array of Asset objects.
    def own_imports
      parse

      @own_imports
    end

    # Internal: Get all imports (including imports of imports).
    #
    # Returns an Array of Asset objects.
    def imports
      unless ran?(:imports)
        parse
        @imports = accumulate(:own_imports)
      end

      @imports
    end

    # Internal: Perform import and reference substitutions based on parse matches.
    #
    # Returns nothing.
    def substitute
      return if ran?(:substitute)

      parse
      substitutions = []

      @parse_matches.sort_by! { |_kind, match, _asset| match.begin(0) }

      @parse_matches.each do |kind, match, asset|
        handler = @delegate.handler(kind)
        handler_args = {
          parse_data: @parse_data,
          match: match,
        }
        handler_args[:asset] = asset if asset

        if !asset && BUILT_IN_PARSE_KINDS.include?(kind)
          add_parse_error(:not_found, match)
          next
        elsif kind == :reference
          entity = match[:entity]
          format = match[:format]

          allowed_formats = REFERENCE_FORMATS[entity]
          format = allowed_formats&.first if format.nil? || format == ''

          handler_args[:format] = format

          if asset.dependencies.include?(self)
            add_parse_error(:circular_reference, match)
            next
          elsif allowed_formats.nil?
            add_parse_error(:unrecognized_reference_entity, match)
            next
          elsif !allowed_formats.include?(format)
            add_parse_error(:unrecognized_reference_format, match)
            next
          elsif entity == 'content' && format != 'base64' && asset.binary?
            add_parse_error(:format_not_base64, match)
            next
          end
        end

        error = catch(:error) do
          substitution, start, finish = handler&.call(**handler_args)

          min_start, max_finish = match.offset(0)
          start ||= !format || format == 'displace' ? min_start : match.begin(:quoted)
          finish ||= !format || format == 'displace' ? max_finish : match.end(:quoted)
          start = start.clamp(min_start, max_finish)
          finish = finish.clamp(min_start, max_finish)

          if kind == :reference
            case "#{match[:entity]}-#{format}"
            when 'path-versioned'
              substitution ||= asset.path_versioned
            when 'path-unversioned'
              substitution ||= asset.path_unversioned
            when 'content-base64'
              quote = DEFAULT_QUOTE if match[:quote] == ''
              data = Base64.strict_encode64(substitution || asset.content)
              substitution = "#{quote}data:#{asset.content_type};base64,#{data}#{quote}"
            when 'content-utf8'
              quote = DEFAULT_QUOTE if match[:quote] == ''
              data = substitution || asset.content
              substitution = "#{quote}data:#{asset.content_type};utf8,#{data}#{quote}"
            when 'content-displace'
              substitution ||= asset.content
            end
          end

          substitutions << [substitution || '', start, finish]
          nil
        end

        add_parse_error(error, match) if error
      end

      substitutions.reverse_each do |content, start, finish|
        @own_content[start...finish] = content
      end
    end

    # Internal: Compile the asset if compilation is supported for the asset's type.
    #
    # Returns nothing.
    def compile
      return if ran?(:compile)

      substitute

      begin
        compiled = @delegate.compile_handler&.call(
          parse_data: @parse_data,
          path: @path,
          own_content: @own_content
        )

        @own_content = compiled if compiled.kind_of?(String)
      rescue StandardError => e
        @errors << e
      ensure
        @own_content.freeze
      end
    end

    # Internal: Get the processed content of the asset without dependencies concatenated.
    #
    # Returns the String result.
    def own_content
      compile

      @own_content
    end

    private

    # Internal: Require any libraries necessary for compiling, finalizing, and minifying the asset based on
    # its type.
    #
    # Darkroom does not explicitly depend on any libraries necessary for asset compilation, finalization, or
    # minification. This is because not every app will use every kind of asset or use minification. It is
    # instead up to each app using Darkroom to specify any needed libraries as direct dependencies (e.g. add
    # gem('terser') to the app's Gemfile if JavaScript minification is desired).
    #
    # Returns nothing.
    # Raises MissingLibraryError if a library cannot be loaded.
    def require_libs
      Delegate::LIB_REQUIRES.each do |need|
        next if need == :minify && !@minify

        begin
          lib = @delegate.send(:"#{need}_lib")
          require(lib) if lib
        rescue LoadError
          raise(MissingLibraryError.new(lib, need, @extension), cause: nil)
        end
      end
    end

    # Internal: Check if a method has already been run during the current round of processing and mark it as
    # having been run if not.
    #
    # name - Symbol name of the method.
    #
    # Returns the boolean result.
    def ran?(name)
      modified?

      if @ran.member?(name)
        true
      else
        @ran << name
        false
      end
    end

    # Internal: Recursively build an array of Asset objects (used by #dependencies and #imports).
    #
    # name - Symbol name of the array to accumulate (:dependencies or :imports).
    #
    # Returns an Array of Asset objects.
    def accumulate(name)
      done = Set.new
      assets = [self]
      index = 0

      while index
        asset = assets[index]
        done << asset
        additional = asset.send(name).reject { |a| done.include?(a) }
        assets.insert(index, *additional).uniq!
        index = assets.index { |a| !done.include?(a) }
      end

      assets.delete(self)
      assets
    end

    # Internal: Create a parse error of the appropriate class and append it to the errors array.
    #
    # error - Symbol error type or String error message.
    # match - MatchData object for where the parse error occurred.
    #
    # Returns nothing.
    # Raises RuntimeError if error is not a String or recognized Symbol error name.
    def add_parse_error(error, match)
      klass = AssetError
      args = [match[0].strip]

      case error
      when :not_found
        path = match[:path]
        delegate = Darkroom.delegate(File.extname(path)) if path
        klass = delegate ? AssetNotFoundError : UnrecognizedExtensionError
        args.clear << path
      when :circular_reference
        klass = CircularReferenceError
      when :unrecognized_reference_entity
        entity = match[:entity].nil? ? 'nil' : "'#{match[:entity]}'"
        allowed = "'#{Asset::REFERENCE_FORMATS.keys.join("', '")}'"
        message = "Invalid reference entity #{entity} (must be one of #{allowed})"
      when :unrecognized_reference_format
        entity = match[:entity]
        format = match[:format].nil? ? 'nil' : "'#{match[:format]}'"
        allowed = "'#{Asset::REFERENCE_FORMATS[entity].join("', '")}'"
        message = "Invalid reference format #{format} (must be one of #{allowed})"
      when :format_not_base64
        message = 'Base64 encoding is required for binary assets'
      else
        message = error.to_s
      end

      args.unshift(message) if message

      @errors << klass.new(*args, @path, @own_content[0..match.begin(:path)].count("\n") + 1)
    end
  end
end
