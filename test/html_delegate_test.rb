# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('asset_test')

class HTMLDelegateTest < Minitest::Test
  include(TestHelper)

  context(Darkroom::HTMLDelegate) do
    ########################################################################################################
    ## ::regex(:reference)                                                                                ##
    ########################################################################################################

    context('::regex(:reference)') do
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
          match = content.match(Darkroom::HTMLDelegate.regex(:reference))

          assert(match)
          assert_equal(path, match[:path])
          assert_equal(entity, match[:entity])
          format ? assert_equal(format, match[:format]) : assert_nil(match[:format])
        end
      end

      test('does not match references with bad syntax') do
        regex = Darkroom::HTMLDelegate.regex(:reference)

        refute_match(regex, %q(<img src= '/logo.svg?asset-path'>))
      end
    end

    ########################################################################################################
    ## ::handler(:reference)                                                                              ##
    ########################################################################################################

    context('::handler(:reference)') do
      test('throws error if <link> tag references non-CSS asset with displace format') do
        error = catch(:error) do
          Darkroom::HTMLDelegate.handler(:reference).call(
            parse_data: {},
            match: reference_match("<link href='/robots.txt?asset-content=displace'>"),
            asset: new_asset('/robots.txt', ''),
            format: 'displace',
          ); nil
        end

        assert_equal('Asset content type must be text/css', error)
      end

      test('throws error if <script> tag references non-JavaScript asset with displace format') do
        error = catch(:error) do
          Darkroom::HTMLDelegate.handler(:reference).call(
            parse_data: {},
            match: reference_match("<script href='/robots.txt?asset-content=displace'></script>"),
            asset: new_asset('/robots.txt', ''),
            format: 'displace',
          ); nil
        end

        assert_equal('Asset content type must be text/javascript', error)
      end

      test('throws error if <img> tag references non-SVG asset with displace format') do
        error = catch(:error) do
          Darkroom::HTMLDelegate.handler(:reference).call(
            parse_data: {},
            match: reference_match("<img src='/robots.txt?asset-content=displace'>"),
            asset: new_asset('/robots.txt', ''),
            format: 'displace',
          ); nil
        end

        assert_equal('Asset content type must be image/svg+xml', error)
      end

      test('throws error if tag is not <link>, <script>, or <img> with displace format') do
        %w[a area audio base embed iframe input source track video].each do |tag|
          error = catch(:error) do
            Darkroom::HTMLDelegate.handler(:reference).call(
              parse_data: {},
              match: reference_match("<#{tag} href='/logo.svg?asset-content=displace'></#{tag}>"),
              asset: new_asset('/logo.svg', ''),
              format: 'displace',
            ); nil
          end

          assert_equal("Cannot displace <#{tag}> tags", error)
        end
      end

      test('returns <style>...</style> for <link> tag reference with displace format') do
        result = Darkroom::HTMLDelegate.handler(:reference).call(
          parse_data: {},
          match: reference_match("<link href='/app.css?asset-content=displace'>"),
          asset: new_asset('/app.css', 'body { background: white; }'),
          format: 'displace',
        )

        assert_equal("<style>body { background: white; }</style>", result)
      end

      test('returns <script>... for <script> tag reference with displace format') do
        result = Darkroom::HTMLDelegate.handler(:reference).call(
          parse_data: {},
          match: reference_match("<script src='/app.js?asset-content=displace'></script>"),
          asset: new_asset('/app.js', "console.log('Hello')"),
          format: 'displace',
        )

        assert_equal('<script>console.log(\'Hello\')', result)
      end

      test('returns SVG content for <img> tag reference with displace format') do
        result = Darkroom::HTMLDelegate.handler(:reference).call(
          parse_data: {},
          match: reference_match("<img src='/logo.svg?asset-content=displace'>"),
          asset: new_asset('/logo.svg', "<svg><circle r='16' fill='#fff'/></svg>"),
          format: 'displace',
        )

        assert_equal("<svg><circle r='16' fill='#fff'/></svg>", result)
      end

      test('encodes # characters with utf8 format') do
        result = Darkroom::HTMLDelegate.handler(:reference).call(
          parse_data: {},
          match: reference_match('<img src="/logo.svg?asset-content=utf8">'),
          asset: new_asset('/logo.svg', "<svg><circle r=16 fill=#fff/></svg>"),
          format: 'utf8',
        )

        assert_equal("<svg><circle r=16 fill=%23fff/></svg>", result)
      end

      test('substitutes single quotes when reference is unquoted with utf8 format') do
        result = Darkroom::HTMLDelegate.handler(:reference).call(
          parse_data: {},
          match: reference_match('<img src=/logo.svg?asset-content=utf8>'),
          asset: new_asset('/logo.svg', '<svg><circle r=\'16\' fill="white"/></svg>'),
          format: 'utf8',
        )

        assert_equal('<svg><circle r=&#39;16&#39; fill="white"/></svg>', result)
      end

      test('substitutes single quotes when reference is single-quoted with utf8 format') do
        result = Darkroom::HTMLDelegate.handler(:reference).call(
          parse_data: {},
          match: reference_match('<img src=\'/logo.svg?asset-content=utf8\'>'),
          asset: new_asset('/logo.svg', '<svg><circle r=\'16\' fill="white"/></svg>'),
          format: 'utf8',
        )

        assert_equal('<svg><circle r=&#39;16&#39; fill="white"/></svg>', result)
      end

      test('substitutes double quotes when reference is double-quoted with utf8 format') do
        result = Darkroom::HTMLDelegate.handler(:reference).call(
          parse_data: {},
          match: reference_match('<img src="/logo.svg?asset-content=utf8">'),
          asset: new_asset('/logo.svg', '<svg><circle r=\'16\' fill="white"/></svg>'),
          format: 'utf8',
        )

        assert_equal('<svg><circle r=\'16\' fill=&#34;white&#34;/></svg>', result)
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
    content.match(Darkroom::HTMLDelegate.regex(:reference))
  end
end
