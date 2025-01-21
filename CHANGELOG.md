# Darkroom Changelog

## Upcoming (Unreleased)

* Nothing yet

## 0.0.9 (2025 January 21)

* **Remove deprecated delegate creation via hash and associated accessors**
* **Remove deprecated `:minified_pattern` option**
* **Remove deprecated `:internal_pattern` option and `Asset#internal?` method**
* **Fix assets with error(s) not getting reprocessed until directly modified**
* Add support for AVIF assets
* Add support for animated PNG assets
* Add support for GIF assets
* Add support for WebP assets

## 0.0.8 (2023 July 15)

* **Fix issues with ensuring previous steps of asset processing**
* **Fix ordering of JavaScript import statements in IIFE output**

## 0.0.7 (2023 July 15)

* **Add option to use IIFEs for JavaScript assets instead of concatenating**
* Add line info to `ProcessingError#to_s` output for non-`AssetError` errors
* Raise error in `Darkroom#dump` if present from last process run
* Yield to parse handlers and accumulate errors in order of appearance
* Add deprecation warning to `Asset#internal?`
* **Add support for importing and referencing assets by relative path**
* Escape quotes with HTML entities in reference content with UTF8 format
* **Implement DSL for delegates and deprecate configuring via hash**
* Move delegate registration back to `Darkroom` class
* Rework asset processing code to reduce chances of asset dependency bugs
* **Deprecate `:minified_pattern` and replace with more flexible `:minified`**
* **Deprecate `:internal_pattern` and replace with more flexible `:entries`**
* Skip exception raise in `Darkroom#process!` if processing was skipped
* Allow compiled assets to be further processed as target content type
* Ensure pristine files are never treated as internal
* Move delegate registration and management to Asset class

## 0.0.6 (2022 May 3)

* Use [Terser](https://github.com/ahorek/terser-ruby) instead of
  [UglifyJS](https://github.com/lautis/uglifier) for JavaScript minification
* **Fix dependencies sometimes getting missed due to circular references**

## 0.0.5 (2022 March 31)

* Ensure load paths are absolute and fully normalized
* **Ensure a dependency has been processed before fetching its dependencies**
* **Remove deprecated `Asset.add_spec` and `Asset.spec` methods**

## 0.0.4 (2021 August 3)

* **Add ability to reference other asset paths and content within an asset**
* Ensure `FileUtils` is loaded when dumping assets to disk
* **Add `Asset#image?` for determining if an asset is an image**
* **Add `Asset#font?` for determining if an asset is a font**
* **Add `Asset#binary?` for determining if an asset is binary**
* Ensure errors array always exists on `Darkroom` instances
* Improve error class organization, naming, and messages
* **Use text/javascript for content type of JavaScript and HTX files**
* Disallow troublesome characters in asset paths
* Add support for JSON assets

## 0.0.3 (2021 March 27)

* Fix and improve quote matching in dependency regexes
* Use [SassC](https://github.com/sass/sassc-ruby) for minifying CSS since it is more up to date than
  [CSSminify](https://github.com/matthiassiegel/cssminify)
* Fix HTML spec to recognize .htm extensions in addition to .html

## 0.0.2 (2021 March 25)

* Improve output of compile and minify library load errors
* **Rework how assets are processed so circular dependencies work properly**
* **Add methods for getting subresource integrity string for an asset**
* **Remove `Darkroom#asset_path!` and move its behavior to `#asset_path`**

## 0.0.1 (2021 February 25)

* Release initial gem
