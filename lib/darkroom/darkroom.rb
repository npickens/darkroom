# frozen_string_literal: true

require('set')

require_relative('asset')
require_relative('errors/asset_not_found_error')
require_relative('errors/duplicate_asset_error')
require_relative('errors/invalid_path_error')
require_relative('errors/processing_error')

##
# Main class providing fast, lightweight, and straightforward web asset management.
#
class Darkroom
  DEFAULT_MINIFIED = /(\.|-)min\.\w+$/.freeze
  TRAILING_SLASHES = /\/+$/.freeze
  PRISTINE = Set.new(%w[/favicon.ico /mask-icon.svg /humans.txt /robots.txt]).freeze
  MIN_PROCESS_INTERVAL = 0.5

  @@delegates = {}
  @@glob = ''

  attr_reader(:error, :errors, :process_key)

  class << self; attr_accessor(:javascript_iife) end

  ##
  # Registers an asset delegate.
  #
  # [*extensions] One or more file extension(s) to associate with this delegate.
  # [delegate] An HTTP MIME type string or a Delegate subclass.
  #
  def self.register(*extensions, delegate, &block)
    if delegate.kind_of?(String)
      content_type = delegate

      if delegate[0] == '.'
        extensions << delegate
        content_type = nil
      end

      delegate = Class.new(Delegate, &block)
      delegate.content_type(content_type) if content_type && !delegate.content_type
    elsif delegate && delegate < Delegate
      delegate = block ? Class.new(delegate, &block) : delegate
    end

    extensions.each do |extension|
      @@delegates[extension] = delegate
    end

    @@glob = "**/*{#{@@delegates.keys.sort.join(',')}}"

    delegate
  end

  ##
  # Returns the delegate associated with a file extension.
  #
  # [extension] File extension of the desired delegate.
  #
  def self.delegate(extension)
    @@delegates[extension]
  end

  ##
  # Utility method that prints a warning with file and line number of a deprecated call.
  #
  def self.deprecated(message)
    location = caller_locations(2, 1).first

    warn("#{location.path}:#{location.lineno}: #{message}")
  end

  ##
  # Creates a new instance.
  #
  # [*load_paths] One or more paths where assets are located on disk.
  # [host:] Host(s) to prepend to paths (useful when serving from a CDN in production). If multiple hosts
  #         are specified, they will be round-robined within each thread for each call to +#asset_path+.
  # [hosts:] Alias of +host:+.
  # [prefix:] Prefix to prepend to asset paths (e.g. +/assets+).
  # [pristine:] Path(s) that should not include prefix and for which unversioned form should be provided by
  #             default (e.g. +/favicon.ico+).
  # [entries:] String, regex, or array of strings and regexes specifying entry point paths / path patterns.
  # [minify:] Boolean specifying whether or not to minify assets.
  # [minified:] String, regex, or array of strings and regexes specifying paths of assets that are already
  #             minified and thus should be skipped for minification.
  # [min_process_interval:] Minimum time required between one run of asset processing and another.
  #
  def initialize(*load_paths, host: nil, hosts: nil, prefix: nil, pristine: nil, entries: nil,
      minify: false, minified: DEFAULT_MINIFIED, min_process_interval: MIN_PROCESS_INTERVAL)
    @load_paths = load_paths.map { |load_path| File.expand_path(load_path) }

    @hosts = (Array(host) + Array(hosts)).map! { |host| host.sub(TRAILING_SLASHES, '') }
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

  ##
  # Walks all load paths and refreshes any assets that have been modified on disk since the last call to
  # this method. Returns false if processing was skipped due to previous call happening less than
  # min_process_interval ago or because another thread was already processing; returns true otherwise.
  #
  def process
    return false if Time.now.to_f - @last_processed_at < @min_process_interval

    if @mutex.locked?
      @mutex.synchronize {}
      return false
    end

    @mutex.synchronize do
      @process_key += 1
      @errors.clear
      found = {}

      @load_paths.each do |load_path|
        Dir.glob(File.join(load_path, @@glob)).sort.each do |file|
          path = file.sub(load_path, '')

          if index = (path =~ Asset::INVALID_PATH_REGEX)
            @errors << InvalidPathError.new(path, index)
          elsif found.key?(path)
            @errors << DuplicateAssetError.new(path, found[path], load_path)
          else
            found[path] = load_path

            unless @manifest.key?(path)
              entry = entry?(path)

              @manifest[path] = Asset.new(path, file, self,
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

      @manifest.each do |path, asset|
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

  ##
  # Calls #process. If processing was skipped, returns false. If processing was performed, raises an
  # exception if any errors were encountered and returns true otherwise.
  #
  def process!
    result = process

    (result && @error) ? raise(@error) : result
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
  # [path] External path of the asset.
  #
  def asset(path)
    @manifest_versioned[path] || @manifest_unversioned[path]
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
  # Raises an AssetNotFoundError if the asset doesn't exist.
  #
  # [path] Internal path of the asset.
  # [versioned:] Boolean indicating whether the versioned or unversioned path should be returned.
  #
  def asset_path(path, versioned: !@pristine.include?(path))
    asset = @manifest[path] or raise(AssetNotFoundError.new(path))
    host = @hosts.empty? ? '' : @hosts[
      Thread.current[:darkroom_host_index] = (Thread.current[:darkroom_host_index] + 1) % @hosts.size
    ]

    "#{host}#{versioned ? asset.path_versioned : asset.path_unversioned}"
  end

  ##
  # Returns an asset's subresource integrity string. Raises an AssetNotFoundError if the asset doesn't
  # exist.
  #
  # [path] Internal path of the asset.
  # [algorithm] Hash algorithm to use to generate the integrity string (see Asset#integrity).
  #
  def asset_integrity(path, algorithm = nil)
    asset = @manifest[path] or raise(AssetNotFoundError.new(path))

    algorithm ? asset.integrity(algorithm) : asset.integrity
  end

  ##
  # Returns the asset from the manifest hash associated with the given path.
  #
  # [path] Internal path of the asset.
  #
  def manifest(path)
    @manifest[path]
  end

  ##
  # Writes assets to disk. This is useful when deploying to a production environment where assets will be
  # uploaded to and served from a CDN or proxy server.
  #
  # [dir] Directory to write the assets to.
  # [clear:] Boolean indicating whether or not the existing contents of the directory should be deleted
  #          before performing the dump.
  # [include_pristine:] Boolean indicating whether or not to include pristine assets (when dumping for the
  #                     purpose of uploading to a CDN, assets such as /robots.txt and /favicon.ico don't
  #                     need to be included).
  #
  def dump(dir, clear: false, include_pristine: true)
    raise(@error) if @error

    require('fileutils')

    dir = File.expand_path(dir)

    FileUtils.mkdir_p(dir)
    Dir.each_child(dir) { |child| FileUtils.rm_rf(File.join(dir, child)) } if clear

    @manifest_versioned.each do |path, asset|
      next if @pristine.include?(asset.path) && !include_pristine

      file_path = File.join(dir,
        @pristine.include?(asset.path) ? asset.path_unversioned : path
      )

      FileUtils.mkdir_p(File.dirname(file_path))
      File.write(file_path, asset.content)
    end
  end

  ##
  # Returns high-level object info string.
  #
  def inspect
    "#<#{self.class} "\
      "@entries=#{@entries.inspect}, "\
      "@errors=#{@errors.inspect}, "\
      "@hosts=#{@hosts.inspect}, "\
      "@last_processed_at=#{@last_processed_at.inspect}, "\
      "@load_paths=#{@load_paths.inspect}, "\
      "@min_process_interval=#{@min_process_interval.inspect}, "\
      "@minified=#{@minified.inspect}, "\
      "@minify=#{@minify.inspect}, "\
      "@prefix=#{@prefix.inspect}, "\
      "@pristine=#{@pristine.inspect}, "\
      "@process_key=#{@process_key.inspect}"\
    '>'
  end

  private

  ##
  # Returns boolean indicating whether or not the provided path is an entry point.
  #
  # [path] Path to check.
  #
  def entry?(path)
    if @pristine.include?(path)
      true
    elsif @entries.empty?
      true
    else
      @entries.any? do |entry|
        path == entry || (entry.kind_of?(Regexp) && path.match?(entry))
      end
    end
  end

  ##
  # Returns boolean indicating whether or not the asset with the provided path is already minified.
  #
  # [path] Path to check.
  #
  def minified?(path)
    @minified.any? do |minified|
      path == minified || (minified.kind_of?(Regexp) && path.match?(minified))
    end
  end
end
