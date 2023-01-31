# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('test_helper')

class CSSDelegateTest < Minitest::Test
  include(TestHelper)

  context('Darkroom::Asset::CSSDelegate') do
    ########################################################################################################
    ## ::import_regex                                                                                     ##
    ########################################################################################################

    context('::import_regex') do
      test('matches import statements with proper syntax') do
        assert_equal('',                   import_path(%q(@import '';)))
        assert_equal('',                   import_path(%q(@import "";)))
        assert_equal('/single-quotes.css', import_path(%q(@import '/single-quotes.css';)))
        assert_equal('/double-quotes.css', import_path(%q(@import "/double-quotes.css";)))
        assert_equal('/whitespace.js',     import_path(%q( @import  '/whitespace.js' ; )))
      end

      test('does not match import statements with bad syntax') do
        regex = Darkroom::Asset::CSSDelegate.import_regex

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
    end

    ########################################################################################################
    ## ::reference_regex                                                                                  ##
    ########################################################################################################

    context('::reference_regex') do
      test('matches references with proper syntax') do
        {
          %q<background: url(/logo.svg?asset-path);>               => ['/logo.svg', 'path', nil],
          %q<background: url( /logo.svg?asset-path );>             => ['/logo.svg', 'path', nil],
          %q<background: url( '/logo.svg?asset-path' );>           => ['/logo.svg', 'path', nil],
          %q<background: url( "/logo.svg?asset-path" );>           => ['/logo.svg', 'path', nil],
          %Q<background: url(\n\t"/logo.svg?asset-path"\n\t);>     => ['/logo.svg', 'path', nil],
          %q<background: url('/logo.svg?asset-path');>             => ['/logo.svg', 'path', nil],
          %q<background: url('/logo.svg?asset-path=versioned');>   => ['/logo.svg', 'path', 'versioned'],
          %q<background: url('/logo.svg?asset-path=unversioned');> => ['/logo.svg', 'path', 'unversioned'],
          %q<background: url('/logo.svg?asset-content');>          => ['/logo.svg', 'content', nil],
          %q<background: url('/logo.svg?asset-content=base64');>   => ['/logo.svg', 'content', 'base64'],
          %q<background: url('/logo.svg?asset-content=utf8');>     => ['/logo.svg', 'content', 'utf8'],
          %q<background: url('/logo.svg?asset-content=displace');> => ['/logo.svg', 'content', 'displace'],
        }.each do |content, (path, entity, format)|
          match = content.match(Darkroom::Asset::CSSDelegate.reference_regex)

          assert(match)
          assert_equal(path, match[:path])
          assert_equal(entity, match[:entity])
          format ? assert_equal(format, match[:format]) : assert_nil(match[:format])
        end
      end

      test('does not match references with bad syntax') do
        regex = Darkroom::Asset::CSSDelegate.reference_regex

        refute_match(regex, %q<background: url '/logo.svg?asset-path'>)
        refute_match(regex, %q<background: url ('/logo.svg?asset-path')>)
        refute_match(regex, %Q<background: url\n(/logo.svg?asset-path)>)
      end
    end

    ########################################################################################################
    ## ::validate_reference                                                                               ##
    ########################################################################################################

    context('::validate_reference') do
      test('returns error with displace format') do
        error = Darkroom::Asset::CSSDelegate.validate_reference.(
          new_asset('/bg.png', ''),
          reference_match("body { background: url('/bg.png?asset-content=displace'); }"),
          'displace',
        )

        assert_equal('Cannot displace in CSS files', error)
      end

      test('returns error if asset is not an image or font') do
        error = Darkroom::Asset::CSSDelegate.validate_reference.(
          new_asset('/robots.txt', ''),
          reference_match("body { background: url('/robots.txt?asset-content'); }"),
          'base64',
        )

        assert_equal('Referenced asset must be an image or font type', error)
      end
    end

    ########################################################################################################
    ## ::reference_content                                                                                ##
    ########################################################################################################

    context('::reference_content') do
      test('escapes # characters with utf8 format') do
        result = Darkroom::Asset::CSSDelegate.reference_content.(
          new_asset('/logo.svg', '<svg><!-- # --></svg>'),
          reference_match("#logo { background: url('/logo.svg?asset-content=utf8'>); }"),
          'utf8',
        )

        assert_equal('<svg><!-- %23 --></svg>', result)
      end

      test('escapes quotes with utf8 format') do
        result = Darkroom::Asset::CSSDelegate.reference_content.(
          new_asset('/logo.svg', '<svg><circle r=\'16\' fill="white"/></svg>'),
          reference_match("#logo { background: url('/logo.svg?asset-content=utf8'); }"),
          'utf8',
        )

        assert_equal('<svg><circle r=\\\'16\\\' fill=\\"white\\"/></svg>', result)
      end

      test('escapes newlines with utf8 format') do
        result = Darkroom::Asset::CSSDelegate.reference_content.(
          new_asset('/logo.svg', "<svg>\n</svg>"),
          reference_match("#logo { background: url('/logo.svg?asset-content=utf8'); }"),
          'utf8',
        )

        assert_equal("<svg>\\\n</svg>", result)
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

  def import_path(content)
    content.match(Darkroom::Asset::CSSDelegate.import_regex)&.[](:path)
  end

  def reference_match(content)
    content.match(Darkroom::Asset::CSSDelegate.reference_regex)
  end
end
