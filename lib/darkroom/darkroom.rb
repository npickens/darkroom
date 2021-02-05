# frozen_string_literal: true

require('set')

require_relative('errors/duplicate_asset_error')
require_relative('errors/asset_not_found_error')
require_relative('errors/processing_error')

##
# Main class providing fast, lightweight, and straightforward web asset management.
#
class Darkroom
  DEFAULT_INTERNAL_PATTERN = nil
  DEFAULT_MINIFIED_PATTERN = /(\.|-)min\.\w+$/.freeze
  PRISTINE = Set.new(%w[/favicon.ico /mask-icon.svg /humans.txt /robots.txt]).freeze
  MIN_PROCESS_INTERVAL = 0.5

  attr_reader(:error, :errors)

  ##
  # Creates a new instance.
  #
  # * +load_paths+ - Path(s) where assets are located on disk.
  # * +host+ - Host(s) to prepend to paths (useful when serving from a CDN in production). If multiple hosts
  #   are specified, they will be round-robined within each thread for each call to +#asset_path+.
  # * +hosts+ - Alias of +host+ parameter.
  # * +prefix+ - Prefix to prepend to asset paths (e.g. +/assets+).
  # * +pristine+ - Path(s) that should not have the prefix or versioning applied (e.g. +/favicon.ico+).
  # * +minify+ - Boolean specifying whether or not to minify assets.
  # * +minified_pattern+ - Regex used against asset paths to determine if they are already minified and
  #   should therefore be skipped over for minification.
  # * +internal_pattern+ - Regex used against asset paths to determine if they should be marked as internal
  #   and therefore made inaccessible externally.
  # * +min_process_interval+ - Minimum time required between one run of asset processing and another.
  #
  def initialize(*load_paths, host: nil, hosts: nil, prefix: nil, pristine: nil, minify: false,
      minified_pattern: DEFAULT_MINIFIED_PATTERN, internal_pattern: DEFAULT_INTERNAL_PATTERN,
      min_process_interval: MIN_PROCESS_INTERVAL)
    @globs = load_paths.each_with_object({}) do |path, globs|
      globs[path.chomp('/')] = File.join(path, '**', "*{#{Asset::SPECS.keys.join(',')}}")
    end

    @hosts = Array(host) + Array(hosts)
    @minify = minify
    @internal_pattern = internal_pattern
    @minified_pattern = minified_pattern

    @prefix = prefix&.sub(/\/+$/, '')
    @prefix = nil if @prefix && @prefix.empty?

    @pristine = PRISTINE.dup.merge(Array(pristine))

    @min_process_interval = min_process_interval
    @last_processed_at = 0
    @mutex = Mutex.new
    @manifest = {}
  end

  ##
  # Refresh any assets that have been modified on disk since the last call to this method.
  #
  def process
    return if Time.now.to_f - @last_processed_at < @min_process_interval

    if @mutex.locked?
      @mutex.synchronize {}
      return
    end

    @mutex.synchronize do
      @errors = []
      found = {}

      @globs.each do |load_path, glob|
        Dir.glob(glob).each do |file|
          path = file.sub(load_path, '')

          if found.key?(path)
            @errors << DuplicateAssetError.new(path, found[path], load_path)
          else
            found[path] = load_path

            @manifest[path] ||= Asset.new(path, file, @manifest,
              internal: internal = @internal_pattern && path =~ @internal_pattern,
              minify: @minify && !internal && path !~ @minified_pattern,
            )
          end
        end
      end

      @manifest.select! { |path, _| found.key?(path) }

      found.each do |path, _|
        @manifest[path].process(@last_processed_at)
        @manifest[@manifest[path].path_versioned] = @manifest[path]

        @errors += @manifest[path].errors
      end
    ensure
      @last_processed_at = Time.now.to_f
      @error =
        if @errors.empty? then nil
        elsif @errors.size == 1 then @errors.first
        else ProcessingError.new(@errors)
        end
    end
  end

  ##
  # Does the same thing as #process, but raises an exception if any errors were encountered.
  #
  def process!
    process

    raise(@error) if @error
  end

  ##
  # Returns boolean indicating whether or not there were any errors encountered the last time assets were
  # processed.
  #
  def error?
    !!@error
  end

  ##
  # Returns an Asset object, given its external path. An external path includes any prefix and and can be
  # either the versioned or unversioned form of the asset path (i.e. how an HTTP request for the asset comes
  # in). For example, to get the Asset object with path +/js/app.js+ when prefix is +/assets+:
  #
  #   darkroom.asset('/assets/js/app.<hash>.js')
  #   darkroom.asset('/assets/js/app.js')
  #
  # * +path+ - The external path of the asset.
  #
  def asset(path)
    if @prefix && !@pristine.include?(path)
      path = path.start_with?(@prefix) ? path.sub(@prefix, '') : nil
      path = nil if @pristine.include?(path)
    end

    asset = @manifest[path] or return nil
    asset if !asset.internal?
  end

  ##
  # Returns the external asset path, given its internal path. An external path includes any prefix and and
  # can be either the versioned or unversioned form of the asset path (i.e. how an HTTP request for the
  # asset comes in). For example, to get the external path for the Asset object with path +/js/app.js+ when
  # prefix is +/assets+:
  #
  #   darkroom.asset_path('/js/app.js')                   # => /assets/js/app.<hash>.js
  #   darkroom.asset_path('/js/app.js', versioned: false) # => /assets/js/app.js
  #
  # * +path+ - The internal path of the asset.
  # * +versioned+ - Boolean indicating whether the versioned or unversioned path should be returned.
  #
  def asset_path(path, versioned: true)
    asset = @manifest[path] or return nil
    prefix = @prefix if @prefix && !@pristine.include?(path)

    if @hosts
      if Thread.current[:darkroom_counter].nil? ||
          Thread.current[:darkroom_counter] >= @hosts.size
        Thread.current[:darkroom_counter] = 0
      end

      host = @hosts[(Thread.current[:darkroom_counter] += 1) % @hosts.size]
    end

    "#{host}#{prefix}#{versioned ? asset.path_versioned : path}"
  end

  ##
  # Calls #asset_path and raises a AssetNotFoundError if the asset doesn't exist (instead of just returning
  # nil).
  #
  def asset_path!(path, versioned: true)
    asset_path(path, versioned: versioned) or raise(AssetNotFoundError.new(path))
  end

  ##
  # Writes assets to disk. This is useful when deploying to a production environment where assets will be
  # uploaded to and served from a CDN or proxy server.
  #
  # * +dir+ - Directory to write the assets to.
  # * +clear+ - Delete existing content of directory before performing dump.
  #
  def dump(dir, clear: false, include_pristine: true)
    dir = File.expand_path(dir)
    written = Set.new

    FileUtils.mkdir_p(dir)
    Dir.new(dir).each_child { |child| FileUtils.rm_rf(File.join(dir, child)) } if clear

    @manifest.each do |_, asset|
      next if asset.internal?
      next if written.include?(asset.path)
      next if @pristine.include?(asset.path) && !include_pristine

      external_path = asset_path(asset.path, versioned: !@pristine.include?(asset.path))
      file_path = File.join(dir, external_path)

      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, asset.content)

      written << asset.path
    end
  end
end
