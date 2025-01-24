# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('test_helper')

class CSSDelegateTest < Minitest::Test
  include(TestHelper)

  ##########################################################################################################
  ## Import Regex                                                                                         ##
  ##########################################################################################################

  test('matches import statements with proper syntax') do
    assert_equal('',                   import_path(%q(@import '';)))
    assert_equal('',                   import_path(%q(@import "";)))
    assert_equal('/single-quotes.css', import_path(%q(@import '/single-quotes.css';)))
    assert_equal('/double-quotes.css', import_path(%q(@import "/double-quotes.css";)))
    assert_equal('/whitespace.js',     import_path(%q( @import  '/whitespace.js' ; )))
  end

  test('does not match import statements with bad syntax') do
    regex = Darkroom::CSSDelegate.regex(:import)

    # Bad quoting
    refute_match(regex, %q(@import /no-quotes.css;))
    refute_match(regex, %q(@import "/mismatched-quotes.css';))
    refute_match(regex, %q(@import '/mismatched-quotes.css";))
    refute_match(regex, %q(@import /missing-open-single-quote.css';))
    refute_match(regex, %q(@import /missing-open-double-quote.css";))
    refute_match(regex, %q(@import '/missing-close-single-quote.css;))
    refute_match(regex, %q(@import "/missing-close-double-quote.css;))

    # Escaped and unescaped quotes
    refute_match(regex, %q(@import '/unescaped'-single-quote.css';))
    refute_match(regex, %q(@import "/unescaped"-double-quote.css";))
    refute_match(regex, %q(@import '/unescaped\\\\'-single-quote.css';))
    refute_match(regex, %q(@import "/unescaped\\\\"-double-quote.css";))
    refute_match(regex, %q(@import '/escaped\\'-single-quote.css';))
    refute_match(regex, %q(@import '/escaped\\\\\\'-single-quote.css';))
    refute_match(regex, %q(@import "/escaped\\"-double-quote.css";))
    refute_match(regex, %q(@import "/escaped\\\\\\"-double-quote.css";))

    # Semicolon
    refute_match(regex, %q(@import '/no-semicolon.css'))
  end

  ##########################################################################################################
  ## Reference Regex                                                                                      ##
  ##########################################################################################################

  test('matches references with proper syntax') do
    {
      %q(background: url(/logo.svg?asset-path);)               => ['/logo.svg', 'path', nil],
      %q(background: url( /logo.svg?asset-path );)             => ['/logo.svg', 'path', nil],
      %q(background: url( '/logo.svg?asset-path' );)           => ['/logo.svg', 'path', nil],
      %q(background: url( "/logo.svg?asset-path" );)           => ['/logo.svg', 'path', nil],
      %Q(background: url(\n\t"/logo.svg?asset-path"\n\t);)     => ['/logo.svg', 'path', nil],
      %q(background: url('/logo.svg?asset-path');)             => ['/logo.svg', 'path', nil],
      %q(background: url('/logo.svg?asset-path=versioned');)   => ['/logo.svg', 'path', 'versioned'],
      %q(background: url('/logo.svg?asset-path=unversioned');) => ['/logo.svg', 'path', 'unversioned'],
      %q(background: url('/logo.svg?asset-content');)          => ['/logo.svg', 'content', nil],
      %q(background: url('/logo.svg?asset-content=base64');)   => ['/logo.svg', 'content', 'base64'],
      %q(background: url('/logo.svg?asset-content=utf8');)     => ['/logo.svg', 'content', 'utf8'],
      %q(background: url('/logo.svg?asset-content=displace');) => ['/logo.svg', 'content', 'displace'],
    }.each do |content, (path, entity, format)|
      match = content.match(Darkroom::CSSDelegate.regex(:reference))

      assert_match(Darkroom::CSSDelegate.regex(:reference), content)
      assert_equal(path, match[:path])
      assert_equal(entity, match[:entity])
      format ? assert_equal(format, match[:format]) : assert_nil(match[:format])
    end
  end

  test('does not match references with bad syntax') do
    regex = Darkroom::CSSDelegate.regex(:reference)

    refute_match(regex, %q(background: url '/logo.svg?asset-path'))
    refute_match(regex, %q(background: url ('/logo.svg?asset-path')))
    refute_match(regex, %Q(background: url\n(/logo.svg?asset-path)))
  end

  ##########################################################################################################
  ## Reference Handler                                                                                    ##
  ##########################################################################################################

  test('throws error on reference with displace format') do
    error = catch(:error) do
      Darkroom::CSSDelegate.handler(:reference).call(
        parse_data: {},
        match: reference_match("body { background: url('/bg.png?asset-content=displace'); }"),
        asset: new_asset('/bg.png', ''),
        format: 'displace',
      )

      nil
    end

    assert_equal('Cannot displace in CSS files', error)
  end

  test('throws error if referenced asset is not an image or font') do
    error = catch(:error) do
      Darkroom::CSSDelegate.handler(:reference).call(
        parse_data: {},
        match: reference_match("body { background: url('/robots.txt?asset-content'); }"),
        asset: new_asset('/robots.txt', ''),
        format: 'base64',
      )

      nil
    end

    assert_equal('Referenced asset must be an image or font type', error)
  end

  test('escapes # characters in references with utf8 format') do
    result = Darkroom::CSSDelegate.handler(:reference).call(
      parse_data: {},
      match: reference_match("#logo { background: url('/logo.svg?asset-content=utf8'>); }"),
      asset: new_asset('/logo.svg', '<svg><!-- # --></svg>'),
      format: 'utf8',
    )

    assert_equal('<svg><!-- %23 --></svg>', result)
  end

  test('escapes quotes in references with utf8 format') do
    result = Darkroom::CSSDelegate.handler(:reference).call(
      parse_data: {},
      match: reference_match("#logo { background: url('/logo.svg?asset-content=utf8'); }"),
      asset: new_asset('/logo.svg', '<svg><circle r=\'16\' fill="white"/></svg>'),
      format: 'utf8',
    )

    assert_equal('<svg><circle r=\\\'16\\\' fill=\\"white\\"/></svg>', result)
  end

  test('escapes newlines in references with utf8 format') do
    result = Darkroom::CSSDelegate.handler(:reference).call(
      parse_data: {},
      match: reference_match("#logo { background: url('/logo.svg?asset-content=utf8'); }"),
      asset: new_asset('/logo.svg', "<svg>\n</svg>"),
      format: 'utf8',
    )

    assert_equal("<svg>\\\n</svg>", result)
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def new_asset(*)
    asset = super
    asset.process

    asset
  end

  def import_path(content)
    content.match(Darkroom::CSSDelegate.regex(:import))&.[](:path)
  end

  def reference_match(content)
    content.match(Darkroom::CSSDelegate.regex(:reference))
  end
end
