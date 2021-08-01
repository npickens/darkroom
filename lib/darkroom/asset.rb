# frozen_string_literal: true

require('base64')
require('digest')

class Darkroom
  ##
  # Represents an asset.
  #
  class Asset
    DEPENDENCY_JOINER = "\n"
    EXTENSION_REGEX = /(?=\.\w+)/.freeze

    @@specs = {}

    attr_reader(:content, :error, :errors, :path, :path_unversioned, :path_versioned)

    ##
    # Holds information about how to handle a particular asset type.
    #
    # * +content_type+ - HTTP MIME type string.
    # * +dependency_regex+ - Regex to match lines of the file against to find dependencies. Must contain a
    #   named component called 'path' (e.g. +/^import (?<path>.*)/+).
    # * +compile+ - Proc to call that will produce the compiled version of the asset's content.
    # * +compile_lib+ - Name of a library to +require+ that is needed by the +compile+ proc.
    # * +minify+ - Proc to call that will produce the minified version of the asset's content.
    # * +minify_lib+ - Name of a library to +require+ that is needed by the +minify+ proc.
    #
    Spec = Struct.new(:content_type, :dependency_regex, :compile, :compile_lib, :minify, :minify_lib)

    ##
    # Defines an asset spec.
    #
    # * +extensions+ - File extensions to associate with this spec.
    # * +content_type+ - HTTP MIME type string.
    # * +other+ - Optional components of the spec (see Spec struct).
    #
    def self.add_spec(*extensions, content_type, **other)
      spec = Spec.new(
        content_type.freeze,
        other[:dependency_regex].freeze,
        other[:compile].freeze,
        other[:compile_lib].freeze,
        other[:minify].freeze,
        other[:minify_lib].freeze,
      ).freeze

      extensions.each do |extension|
        @@specs[extension] = spec
      end

      spec
    end

    ##
    # Returns the spec associated with a file extension.
    #
    # * +extension+ - File extension of the desired spec.
    #
    def self.spec(extension)
      @@specs[extension]
    end

    ##
    # Returns an array of file extensions for which specs exist.
    #
    def self.extensions
      @@specs.keys
    end

    ##
    # Creates a new instance.
    #
    # * +file+ - The path to the file on disk.
    # * +path+ - The path this asset will be referenced by (e.g. /js/app.js).
    # * +darkroom+ - Darkroom instance that the asset is a member of.
    # * +prefix+ - Prefix to apply to unversioned and versioned paths.
    # * +minify+ - Boolean specifying whether or not the asset should be minified when processed.
    # * +internal+ - Boolean indicating whether or not the asset is only accessible internally (i.e. as a
    #   dependency).
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
      @spec = self.class.spec(@extension) or raise(UnrecognizedExtensionError.new(@path))

      require_libs
      clear
    end

    ##
    # Processes the asset if modified (see #modified? for how modification is determined). File is read from
    # disk, any dependencies are merged into its content (if spec for the asset type allows for it), the
    # content is compiled (if the asset type requires compilation), and minified (if specified for this
    # Asset). Returns true if asset was modified since it was last processed and false otherwise.
    #
    def process
      @process_key == @darkroom.process_key ? (return @processed) : (@process_key = @darkroom.process_key)
      modified? ? (@processed = true) : (return @processed = false)

      clear
      read
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
      @spec.content_type
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
    # * +algorithm+ - The hash algorithm to use to generate the integrity string (one of sha256, sha384, or
    #   sha512).
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
    # * +ancestors+ - Ancestor chain followed to get to this asset as a dependency.
    #
    def dependencies(ancestors = Set.new)
      @dependencies ||= @own_dependencies.inject([]) do |dependencies, own_dependency|
        next dependencies if ancestors.include?(self)

        ancestors << self
        own_dependency.process

        dependencies |= own_dependency.dependencies(ancestors)
        dependencies |= [own_dependency]

        dependencies.delete(self)
        ancestors.delete(self)

        dependencies
      end
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
      @error = nil
      @fingerprint = nil
      @path_versioned = nil

      (@errors ||= []).clear
      (@own_dependencies ||= []).clear
      (@content ||= +'').clear
      (@own_content ||= +'').clear
      (@integrity ||= {}).clear
    end

    ##
    # Reads the asset file, building dependency array if dependencies are supported for the asset's type.
    #
    def read
      unless @spec.dependency_regex
        @own_content = File.read(@file)
        return
      end

      File.new(@file).each.with_index do |line, line_num|
        if (path = line[@spec.dependency_regex, :path])
          if (dependency = @darkroom.manifest(path))
            @own_dependencies << dependency
          else
            @errors << AssetNotFoundError.new(path, @path, line_num + 1)
          end
        else
          @own_content << line
        end
      end

      @content << dependencies.map { |d| d.own_content }.join(DEPENDENCY_JOINER)
    end

    ##
    # Compiles the asset if compilation is supported for the asset's type.
    #
    def compile
      if @spec.compile
        begin
          @own_content = @spec.compile.call(@path, @own_content)
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
      if @spec.minify && @minify && !@internal
        begin
          @content = @spec.minify.call(@content)
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
    # (e.g. specify +gem('uglifier')+ in the app's Gemfile if JavaScript minification is desired).
    #
    def require_libs
      begin
        require(@spec.compile_lib) if @spec.compile_lib
      rescue LoadError
        compile_load_error = true
      end

      begin
        require(@spec.minify_lib) if @spec.minify_lib && @minify
      rescue LoadError
        minify_load_error = true
      end

      raise(MissingLibraryError.new(@spec.compile_lib, 'compile', @extension)) if compile_load_error
      raise(MissingLibraryError.new(@spec.minify_lib, 'minify', @extension)) if minify_load_error
    end
  end
end
