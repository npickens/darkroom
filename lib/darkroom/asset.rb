# frozen_string_literal: true

require('digest')

class Darkroom
  ##
  # Represents an asset.
  #
  class Asset
    DEPENDENCY_JOINER = "\n"
    EXTENSION_REGEX = /(?=\.\w+)/.freeze

    @@specs = {}

    attr_reader(:content, :error, :errors, :path, :path_versioned)

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
    # * +manifest+ - Manifest hash from the Darkroom instance that the asset is a member of.
    # * +minify+ - Boolean specifying whether or not the asset should be minified when processed.
    # * +internal+ - Boolean indicating whether or not the asset is only accessible internally (i.e. as a
    #   dependency).
    #
    def initialize(path, file, manifest, minify: false, internal: false)
      @path = path
      @file = file
      @manifest = manifest
      @minify = minify
      @internal = internal

      @extension = File.extname(@path).downcase
      @spec = self.class.spec(@extension) or raise(SpecNotDefinedError.new(@extension, @file))

      require_libs
      clear
    end

    ##
    # Processes the asset if necessary (file's mtime is compared to the last time it was processed). File is
    # read from disk, any dependencies are merged into its content (if spec for the asset type allows for
    # it), the content is compiled (if the asset type requires compilation), and minified (if specified for
    # this Asset). Returns true if asset was modified since it was last processed and false otherwise.
    #
    # * +key+ - Unique value associated with the current round of processing.
    #
    def process(key)
      key == @process_key ? (return @modified) : (@process_key = key)

      begin
        @modified = @mtime != (@mtime = File.mtime(@file))
        @modified ||= @dependencies.any? { |d| d.process(key) }

        return false unless @modified
      rescue Errno::ENOENT
        clear
        return @modified = true
      end

      clear
      read(key)
      compile
      minify

      @fingerprint = Digest::MD5.hexdigest(@content)
      @path_versioned = @path.sub(EXTENSION_REGEX, "-#{@fingerprint}")

      @modified
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
        "@path_versioned=#{@path_versioned.inspect}"\
      '>'
    end

    protected

    ##
    # Returns the processed content of the asset without dependencies concatenated.
    #
    def own_content
      @own_content
    end

    ##
    # Returns an array of all the asset's dependencies.
    #
    def dependencies
      @dependencies
    end

    private

    ##
    # Clears content, dependencies, and errors so asset is ready for (re)processing.
    #
    def clear
      (@errors ||= []).clear
      (@dependencies ||= []).clear
      (@content ||= +'').clear
      (@own_content ||= +'').clear
    end

    ##
    # Reads the asset file, building dependency array if dependencies are supported for the asset's type.
    #
    # * +key+ - Unique value associated with the current round of processing.
    #
    def read(key)
      if @spec.dependency_regex
        dependencies = []

        File.new(@file).each.with_index do |line, line_num|
          if (path = line[@spec.dependency_regex, :path])
            if (dependency = @manifest[path])
              dependencies << dependency
            else
              @errors << AssetNotFoundError.new(path, @path, line_num + 1)
            end
          else
            @own_content << line
          end
        end

        dependencies.each do |dependency|
          dependency.process(key)

          @dependencies += dependency.dependencies
          @dependencies << dependency
        end

        @dependencies.uniq!
        @dependencies.delete_if { |d| d.path == @path }

        @content << @dependencies.map { |d| d.own_content }.join(DEPENDENCY_JOINER)
        @own_content
      else
        @own_content = File.read(@file)
      end
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
        raise(MissingLibraryError.new(@spec.compile_lib, 'compile', @extension))
      end

      begin
        require(@spec.minify_lib) if @spec.minify_lib && @minify
      rescue LoadError
        raise(MissingLibraryError.new(@spec.minify_lib, 'minify', @extension))
      end
    end
  end
end
