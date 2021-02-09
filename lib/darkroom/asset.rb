# frozen_string_literal: true

require('digest')

class Darkroom
  ##
  # Represents an asset.
  #
  class Asset
    DEPENDENCY_JOINER = "\n"
    EXTENSION_REGEX = /(?=\.\w+)/.freeze

    SPECS = Hash[*{
      '.css' => {
        content_type: 'text/css',
        dependency_regex: /^ *@import +(?<quote>['"]) *(?<path>.*) *\g<quote> *; *$/.freeze,
        minify: -> (content) { CSSminify.compress(content) },
        minify_lib: 'cssminify',
      },

      '.htx' => {
        content_type: 'application/javascript',
        compile: -> (path, content) { HTX.compile(path, content) },
        compile_lib: 'htx',
        minify: -> (content) { Uglifier.compile(content, harmony: true) },
        minify_lib: 'uglifier',
      },

      '.js' => {
        content_type: 'application/javascript',
        dependency_regex: /^ *import +(?<quote>['"])(?<path>.*)\g<quote> *;? *$/.freeze,
        minify: -> (content) { Uglifier.compile(content, harmony: true) },
        minify_lib: 'uglifier',
      },

      ['.htm', '.html'] => {content_type: 'text/html'},
      '.ico' => {content_type: 'image/x-icon'},
      ['.jpg', '.jpeg'] => {content_type: 'image/jpeg'},
      '.png' => {content_type: 'image/png'},
      '.svg' => {content_type: 'image/svg+xml'},
      '.txt' => {content_type: 'text/plain'},
      '.woff' => {content_type: 'font/woff'},
      '.woff2' => {content_type: 'font/woff2'},
    }.map { |ext, spec| [ext].flatten.map { |ext| [ext, spec] } }.flatten].freeze

    attr_reader(:content, :error, :errors, :path, :path_versioned)

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
      @spec = SPECS[@extension]

      clear
      load_spec
    end

    ##
    # Processes the asset if necessary (file's mtime is compared to the last time it was processed). File is
    # read from disk, any dependencies are merged into its content (if spec for the asset type allows for
    # it), the content is compiled (if the asset type requires compilation), and minified (if specified for
    # this Asset).
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
      @error =
        if @errors.empty? then nil
        elsif @errors.size == 1 then @errors.first
        else ProcessingError.new(@errors)
        end
    end

    ##
    # Returns the HTTP MIME type string.
    #
    def content_type
      @spec[:content_type]
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
      vars = instance_variables.map do |v|
        "#{v}=#{
          v == :@content || v == :@own_content ? '...' : instance_variable_get(v).inspect
        }"
      end

      "#<#{self.class}:0x%016x #{vars.join(', ')}>" % (object_id * 2)
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
      if @spec[:dependency_regex]
        dependencies = []

        File.new(@file).each.with_index do |line, line_num|
          if (path = line[@spec[:dependency_regex], :path])
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
      @own_content = @spec[:compile].call(@path, @own_content) if @spec[:compile]
      @content << @own_content
    rescue => e
      @errors << e
    end

    ##
    # Minifies the asset if minification is supported for the asset's type, asset is marked as minifiable
    # (i.e. it's not already minified), and the asset is not marked as internal-only.
    #
    def minify
      @content = @spec[:minify].call(@content) if @spec[:minify] && @minify && !@internal
    rescue => e
      @errors << e
    end

    ##
    # Requires any libraries necessary for compiling and minifying the asset based on its type. Throws a
    # MissingLibraryError if library cannot be loaded.
    #
    # Darkroom does not explicitly depend on any libraries necessary for asset compilation or minification,
    # since not every app will use every kind of asset or use minification. It is instead up to each app
    # using Darkroom to specify any needed compilation and minification libraries as direct dependencies
    # (e.g. specify +gem('uglifier')+ in the app's Gemfile if JavaScript minification is desired).
    #
    def load_spec
      return true if @spec_loaded

      begin
        require(@spec[:compile_lib]) if @spec[:compile_lib]
      rescue LoadError
        raise(MissingLibraryError.new(@spec[:compile_lib], 'compile', @extension))
      end

      begin
        require(@spec[:minify_lib]) if @spec[:minify_lib] && @minify
      rescue LoadError
        raise(MissingLibraryError.new(@spec[:minify_lib], 'minify', @extension))
      end

      @spec_loaded = true
    end
  end
end
