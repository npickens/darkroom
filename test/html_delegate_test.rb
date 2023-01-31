# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('asset_test')

class HTMLDelegateTest < Minitest::Test
  include(TestHelper)

  context('Darkroom::Asset::HTMLDelegate') do
    ########################################################################################################
    ## ::reference_regex                                                                                  ##
    ########################################################################################################

    context('::reference_regex') do
      test('matches references with proper syntax') do
        {
          %q(<img src=/logo.svg?asset-path>)               => ['/logo.svg', 'path', nil],
          %q(<img src=/logo.svg?asset-path alt='Hello'>)   => ['/logo.svg', 'path', nil],
          %q(<img src='/logo.svg?asset-path'>)             => ['/logo.svg', 'path', nil],
          %q(<img src='/logo.svg?asset-path=versioned'>)   => ['/logo.svg', 'path', 'versioned'],
          %q(<img src='/logo.svg?asset-path=unversioned'>) => ['/logo.svg', 'path', 'unversioned'],
          %q(<img src='/logo.svg?asset-content'>)          => ['/logo.svg', 'content', nil],
          %q(<img src='/logo.svg?asset-content=base64'>)   => ['/logo.svg', 'content', 'base64'],
          %q(<img src='/logo.svg?asset-content=utf8'>)     => ['/logo.svg', 'content', 'utf8'],
          %q(<img src='/logo.svg?asset-content=displace'>) => ['/logo.svg', 'content', 'displace'],
        }.each do |content, (path, entity, format)|
          match = content.match(Darkroom::Asset::HTMLDelegate.reference_regex)

          assert(match)
          assert_equal(path, match[:path])
          assert_equal(entity, match[:entity])
          format ? assert_equal(format, match[:format]) : assert_nil(match[:format])
        end
      end

      test('does not match references with bad syntax') do
        regex = Darkroom::Asset::HTMLDelegate.reference_regex

        refute_match(regex, %q(<img src= '/logo.svg?asset-path'>))
      end
    end

    ########################################################################################################
    ## ::validate_reference                                                                               ##
    ########################################################################################################

    context('::validate_reference') do
      test('returns error if <link> tag references non-CSS asset with displace format') do
        error = Darkroom::Asset::HTMLDelegate.validate_reference.(
          new_asset('/robots.txt'),
          reference_match("<link href='/robots.txt?asset-content=displace'>"),
          'displace',
        )

        assert_equal('Asset type must be text/css', error)
      end

      test('returns no error if <link> tag references CSS asset with displace format') do
        error = Darkroom::Asset::HTMLDelegate.validate_reference.(
          new_asset('/app.css'),
          reference_match("<link href='/app.css?asset-content=displace'>"),
          'displace',
        )

        refute(error)
      end

      test('returns error if <script> tag references non-JavaScript asset with displace format') do
        error = Darkroom::Asset::HTMLDelegate.validate_reference.(
          new_asset('/robots.txt'),
          reference_match("<script href='/robots.txt?asset-content=displace'></script>"),
          'displace',
        )

        assert_equal('Asset type must be text/javascript', error)
      end

      test('returns no error if <script> tag references JavaScript asset with displace format') do
        error = Darkroom::Asset::HTMLDelegate.validate_reference.(
          new_asset('/app.js'),
          reference_match("<script src='/app.js?asset-content=displace'></script>"),
          'displace',
        )

        refute(error)
      end

      test('returns error if <img> tag references non-SVG asset with displace format') do
        error = Darkroom::Asset::HTMLDelegate.validate_reference.(
          new_asset('/robots.txt'),
          reference_match("<img src='/robots.txt?asset-content=displace'>"),
          'displace',
        )

        assert_equal('Asset type must be image/svg+xml', error)
      end

      test('returns no error if <img> tag references SVG asset with displace format') do
        error = Darkroom::Asset::HTMLDelegate.validate_reference.(
          new_asset('/logo.svg'),
          reference_match("<img src='/logo.svg?asset-content=displace'>"),
          'displace',
        )

        refute(error)
      end

      test('returns error if tag isn\'t <link>, <script>, or <img> with displace format') do
        %w[a area audio base embed iframe input source track video].each do |tag|
          error = Darkroom::Asset::HTMLDelegate.validate_reference.(
            new_asset('/logo.svg'),
            reference_match("<#{tag} href='/logo.svg?asset-content=displace'></#{tag}>"),
            'displace',
          )

          assert_equal("Cannot displace <#{tag}> tags", error)
        end
      end
    end

    ########################################################################################################
    ## ::reference_content                                                                                ##
    ########################################################################################################

    context('::reference_content') do
      test('returns <style>...</style> for <link> tag reference with displace format') do
        result = Darkroom::Asset::HTMLDelegate.reference_content.(
          new_asset('/app.css', 'body { background: white; }'),
          reference_match("<link href='/app.css?asset-content=displace'>"),
          'displace',
        )

        assert_equal("<style>body { background: white; }</style>", result)
      end

      test('returns <script>... for <script> tag reference with displace format') do
        result = Darkroom::Asset::HTMLDelegate.reference_content.(
          new_asset('/app.js', "console.log('Hello')"),
          reference_match("<script src='/app.js?asset-content=displace'></script>"),
          'displace',
        )

        assert_equal('<script>console.log(\'Hello\')', result)
      end

      test('returns SVG content for <img> tag reference with displace format') do
        result = Darkroom::Asset::HTMLDelegate.reference_content.(
          new_asset('/logo.svg', "<svg><circle r='16' fill='#fff'/></svg>"),
          reference_match("<img src='/logo.svg?asset-content=displace'>"),
          'displace',
        )

        assert_equal("<svg><circle r='16' fill='#fff'/></svg>", result)
      end

      test('escapes # characters with utf8 format') do
        result = Darkroom::Asset::HTMLDelegate.reference_content.(
          new_asset('/logo.svg', "<svg><circle r='16' fill='#fff'/></svg>"),
          reference_match('<img src="/logo.svg?asset-content=utf8">'),
          'utf8',
        )

        assert_equal("<svg><circle r='16' fill='%23fff'/></svg>", result)
      end

      test('substitutes quotes if needed with utf8 format') do
        result = Darkroom::Asset::HTMLDelegate.reference_content.(
          new_asset('/logo.svg', '<svg><circle r=\'16\' fill="white"/></svg>'),
          reference_match("<img src='/logo.svg?asset-content=utf8'>"),
          'utf8',
        )

        assert_equal('<svg><circle r="16" fill="white"/></svg>', result)
      end
    end
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def new_asset(*)
    asset = super
    asset.process

    asset
  end

  def reference_match(content)
    content.match(Darkroom::Asset::HTMLDelegate.reference_regex)
  end
end
