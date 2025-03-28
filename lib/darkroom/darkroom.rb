# frozen_string_literal: true

require('set')

require_relative('asset')
require_relative('delegate')
require_relative('errors/asset_not_found_error')
require_relative('errors/duplicate_asset_error')
require_relative('errors/invalid_path_error')
require_relative('errors/processing_error')

# Main class providing simple and straightforward web asset management.
class Darkroom
  DEFAULT_MINIFIED = /(\.|-)min\.\w+$/
  TRAILING_SLASHES = %r{/+$}
  PRISTINE = Set.new(%w[/favicon.ico /mask-icon.svg /humans.txt /robots.txt]).freeze
  MIN_PROCESS_INTERVAL = 0.5

  @@delegates = {}
  @@glob = ''

  attr_reader(:error, :errors, :process_key)

  class << self; attr_accessor(:javascript_iife) end

  # Public: Register a delegate for handling a specific kind of asset.
  #
  # args  - One or more String file extensions to associate with this delegate, optionally followed by
  #         either an HTTP MIME type String or a Delegate subclass.
  # block - Block to call that defines or extends the Delegate.
  #
  # Examples
  #
  #   Darkroom.register('.ext1', '.ext2', 'content/type')
  #   Darkroom.register('.ext', MyDelegateSubclass)
  #
  #   Darkroom.register('.scss', 'text/css') do
  #     compile(lib: 'sassc') { ... }
  #   end
  #
  #   Darkroom.register('.scss', SCSSDelegate) do
  #     # Modifications/overrides of the SCSSDelegate class...
  #   end
  #
  # Returns the Delegate class.
  def self.register(*args, &block)
    last_arg = args.pop unless args.last.kind_of?(String) && args.last[0] == '.'
    extensions = args

    if last_arg.nil? || last_arg.kind_of?(String)
      content_type = last_arg
      delegate = Class.new(Delegate, &block)
      delegate.content_type(content_type) if content_type && !delegate.content_type
    elsif last_arg.kind_of?(Class) && last_arg < Delegate
      delegate = block ? Class.new(last_arg, &block) : last_arg
    end

    extensions.each do |extension|
      @@delegates[extension] = delegate
    end

    @@glob = "**/*{#{@@delegates.keys.sort.join(',')}}"

    delegate
  end

  # Public: Get the Delegate associated with a file extension.
  #
  # extension - String file extension of the desired delegate (e.g. '.js')
  #
  # Returns the Delegate class.
  def self.delegate(extension)
    @@delegates[extension]
  end

  # Public: Create a new instance.
  #
  # load_paths            - One or more String paths where assets are located on disk.
  # host:                 - String host or Array of String hosts to prepend to paths (useful when serving
  #                         from a CDN in production). If multiple hosts are specified, they will be round-
  #                         robined within each thread for each call to #asset_path.
  # hosts:                - String or Array of Strings (alias of host:).
  # prefix:               - String prefix to prepend to asset paths (e.g. '/assets').
  # pristine:             - String, Array of String, or Set of String paths that should not include the
  #                         prefix and for which the unversioned form should be provided by default (e.g.
  #                         '/favicon.ico').
  # entries:              - String, Regexp, or Array of String and/or Regexp specifying entry point paths /
  #                         path patterns.
  # minify:               - Boolean specifying if assets that support it should be minified.
  # minified:             - String, Regexp, or Array of String and/or Regexp specifying paths of assets that
  #                         are already minified and thus shouldn't be minified.
  # min_process_interval: - Numeric minimum number of seconds required between one run of asset processing
  #                         and another.
  def initialize(*load_paths, host: nil, hosts: nil, prefix: nil, pristine: nil, entries: nil,
                 minify: false, minified: DEFAULT_MINIFIED, min_process_interval: MIN_PROCESS_INTERVAL)
    @load_paths = load_paths.map { |load_path| File.expand_path(load_path) }

    @hosts = (Array(host) + Array(hosts)).map! { |h| h.sub(TRAILING_SLASHES, '') }
    @entries = Array(entries)
    @minify = minify
    @minified = Array(minified)

    @prefix = prefix&.sub(TRAILING_SLASHES, '')
    @prefix = nil if @prefix && @prefix.empty?

    @pristine = PRISTINE.dup.merge(Array(pristine))

    @min_process_interval = min_process_interval
    @last_processed_at = 0
    @process_key = 0
    @mutex = Mutex.new

    @manifest = {}
    @manifest_unversioned = {}
    @manifest_versioned = {}

    @errors = []

    Thread.current[:darkroom_host_index] = -1 unless @hosts.empty?
  end

  # Public: Walk all load paths and refresh any assets that have been modified on disk since the last call
  # to this method. Processing is skipped if either a) a previous call to this method happened
  # less than min_process_interval seconds ago or b) another thread is currently executing this method.
  #
  # A mutex is used to ensure that, say, multiple web request threads do not trample each other. If the
  # mutex is locked when this method is called, it will wait until the mutex is released to ensure that the
  # caller does not then start working with stale / invalid Asset objects due to the work of the other
  # thread's active call to #process being incomplete.
  #
  # If any errors are encountered during processing, they must be checked for manually afterward via #error
  # or #errors. If a raise is preferred, use #process! instead.
  #
  # Returns boolean indicating if processing actually happened (true) or was skipped (false).
  def process
    return false if Time.now.to_f - @last_processed_at < @min_process_interval

    if @mutex.locked?
      @mutex.synchronize {} # Wait until other #process call is done to avoid stale/invalid assets.
      return false
    end

    @mutex.synchronize do
      @process_key += 1
      @errors.clear
      found = {}

      @load_paths.each do |load_path|
        Dir.glob(File.join(load_path, @@glob)).each do |file|
          path = file.sub(load_path, '')

          if (index = path.index(Asset::INVALID_PATH_REGEX))
            @errors << InvalidPathError.new(path, index)
          elsif found.key?(path)
            @errors << DuplicateAssetError.new(path, found[path], load_path)
          else
            found[path] = load_path

            unless @manifest.key?(path)
              entry = entry?(path)

              @manifest[path] = Asset.new(
                path, file, self,
                prefix: (@prefix unless @pristine.include?(path)),
                entry: entry,
                minify: entry && @minify && !minified?(path),
              )
            end
          end
        end
      end

      @manifest.select! { |path, _| found.key?(path) }
      @manifest_unversioned.clear
      @manifest_versioned.clear

      @manifest.each_value do |asset|
        asset.process

        if asset.entry?
          @manifest_unversioned[asset.path_unversioned] = asset
          @manifest_versioned[asset.path_versioned] = asset
        end

        @errors.concat(asset.errors)
      end

      true
    ensure
      @last_processed_at = Time.now.to_f
      @error = @errors.empty? ? nil : ProcessingError.new(@errors)
    end
  end

  # Public: Call #process but raise an error if there were errors.
  #
  # Returns boolean indicating if processing actually happened (true) or was skipped (false).
  # Raises ProcessingError if processing actually happened from this call and error(s) were encountered.
  def process!
    result = process

    result && @error ? raise(@error) : result
  end

  # Public: Check if there were any errors encountered the last time assets were processed.
  #
  # Returns the boolean result.
  def error?
    !!@error
  end

  # Public: Get an Asset object, given its external path. An external path includes any prefix and can be
  # either the versioned or unversioned form (i.e. how an HTTP request for the asset comes in).
  #
  # Examples
  #
  #   # Suppose the asset's internal path is '/js/app.js' and the prefix is '/assets'.
  #   darkroom.asset('/assets/js/app-<hash>.js') # => #<Darkroom::Asset [...]>
  #   darkroom.asset('/assets/js/app.js')        # => #<Darkroom::Asset [...]>
  #
  # path - String external path of the asset.
  #
  # Returns the Asset object if it exists or nil otherwise.
  def asset(path)
    @manifest_versioned[path] || @manifest_unversioned[path]
  end

  # Public: Get the external asset path, given its internal path. An external path includes any prefix and
  # can be either the versioned or unversioned form (i.e. how an HTTP request for the asset comes in).
  #
  # path       - String internal path of the asset.
  # versioned: - Boolean specifying either the versioned or unversioned path to be returned.
  #
  # Examples
  #
  #   # Suppose the asset's internal path is '/js/app.js' and the prefix is '/assets'.
  #   darkroom.asset_path('/js/app.js')                   # => "/assets/js/app-<hash>.js"
  #   darkroom.asset_path('/js/app.js', versioned: false) # => "/assets/js/app.js"
  #
  # Returns the String external asset path.
  # Raises AssetNotFoundError if the asset doesn't exist.
  def asset_path(path, versioned: !@pristine.include?(path))
    asset = @manifest[path] or raise(AssetNotFoundError.new(path))

    unless @hosts.empty?
      host_index = (Thread.current[:darkroom_host_index] + 1) % @hosts.size
      host = @hosts[host_index]

      Thread.current[:darkroom_host_index] = host_index
    end

    "#{host}#{versioned ? asset.path_versioned : asset.path_unversioned}"
  end

  # Public: Get an asset's subresource integrity string.
  #
  # path      - String internal path of the asset.
  # algorithm - Symbol hash algorithm name to use to generate the integrity string (must be one of
  #             :sha256, :sha384, :sha512).
  #
  # Returns the asset's subresource integrity String.
  # Raises AssetNotFoundError if the asset doesn't exist.
  def asset_integrity(path, algorithm = nil)
    asset = @manifest[path] or raise(AssetNotFoundError.new(path))

    algorithm ? asset.integrity(algorithm) : asset.integrity
  end

  # Public: Get the Asset object from the manifest Hash associated with the given path.
  #
  # path - String internal path of the asset.
  #
  # Returns the Asset object if it exists or nil otherwise.
  def manifest(path)
    @manifest[path]
  end

  # Public: Write assets to disk. This is useful when deploying to a production environment where assets
  # will be uploaded to and served from a CDN or proxy server. Note that #process must be called manually
  # before calling this method.
  #
  # dir               - String directory path to write the assets to.
  # clear:            - Boolean indicating if the existing contents of the directory should be deleted
  #                     before writing files.
  # include_pristine: - Boolean indicating if pristine assets should be included (when dumping for the
  #                     purpose of uploading to a CDN, assets such as /robots.txt and /favicon.ico don't
  #                     need to be included).
  # gzip:             - Boolean indicating if gzipped versions of non-binary assets should be generated (in
  #                     addition to non-gzipped versions).
  #
  # Returns nothing.
  # Raises ProcessingError if errors were encountered during the last #process run.
  def dump(dir, clear: false, include_pristine: true, gzip: false)
    raise(@error) if @error

    require('fileutils')
    require('zlib') if gzip

    dir = File.expand_path(dir)

    FileUtils.mkdir_p(dir)
    Dir.each_child(dir) { |child| FileUtils.rm_rf(File.join(dir, child)) } if clear

    @manifest_versioned.each do |path_versioned, asset|
      is_pristine = @pristine.include?(asset.path)
      file_path = File.join(dir, is_pristine ? asset.path_unversioned : path_versioned)

      next if is_pristine && !include_pristine

      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, asset.content)

      if gzip && !asset.binary?
        mtime = File.mtime(file_path)
        file_path_gz = "#{file_path}.gz"

        Zlib::GzipWriter.open(file_path_gz) do |file|
          file.mtime = mtime.to_i
          file.write(asset.content)
        end

        File.utime(File.atime(file_path_gz), mtime, file_path_gz)
      end
    end
  end

  # Public: Get a high-level object info string about this Darkroom instance.
  #
  # Returns the String.
  def inspect
    "#<#{self.class} " \
      "@entries=#{@entries.inspect}, " \
      "@errors=#{@errors.inspect}, " \
      "@hosts=#{@hosts.inspect}, " \
      "@last_processed_at=#{@last_processed_at.inspect}, " \
      "@load_paths=#{@load_paths.inspect}, " \
      "@min_process_interval=#{@min_process_interval.inspect}, " \
      "@minified=#{@minified.inspect}, " \
      "@minify=#{@minify.inspect}, " \
      "@prefix=#{@prefix.inspect}, " \
      "@pristine=#{@pristine.inspect}, " \
      "@process_key=#{@process_key.inspect}" \
    '>'
  end

  private

  # Internal: Check if an asset's path indicates that it's an entry point.
  #
  # path - String asset path to check.
  #
  # Returns the boolean result.
  def entry?(path)
    if @pristine.include?(path) || @entries.empty?
      true
    else
      @entries.any? do |entry|
        path == entry || (entry.kind_of?(Regexp) && path.match?(entry))
      end
    end
  end

  # Internal: Check if an asset's path indicates that it's already minified.
  #
  # path - String asset path to check.
  #
  # Returns the boolean result.
  def minified?(path)
    @minified.any? do |minified|
      path == minified || (minified.kind_of?(Regexp) && path.match?(minified))
    end
  end
end
