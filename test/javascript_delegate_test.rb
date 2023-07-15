# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('test_helper')

class JavaScriptDelegateTest < Minitest::Test
  include(TestHelper)

  context(Darkroom::JavaScriptDelegate) do
    ########################################################################################################
    ## ::regex(:import)                                                                                   ##
    ########################################################################################################

    context('::regex(:import)') do
      test('matches import statements with proper syntax') do
        assert_equal('',                            import_path(%q(import '')))
        assert_equal('',                            import_path(%q(import "")))
        assert_equal('/single-quotes.js',           import_path(%q(import '/single-quotes.js')))
        assert_equal('/double-quotes.js',           import_path(%q(import "/double-quotes.js")))
        assert_equal('/single-quotes-semicolon.js', import_path(%q(import '/single-quotes-semicolon.js';)))
        assert_equal('/double-quotes-semicolon.js', import_path(%q(import "/double-quotes-semicolon.js";)))
        assert_equal('/whitespace.js',              import_path(%q( import  '/whitespace.js' ; )))
      end

      test('does not match import statements with bad syntax') do
        regex = Darkroom::JavaScriptDelegate.regex(:import)

        # Bad quoting
        refute_match(regex, %q(import /no-quotes.js))
        refute_match(regex, %q(import "/mismatched-quotes.js'))
        refute_match(regex, %q(import '/mismatched-quotes.js"))
        refute_match(regex, %q(import /missing-open-single-quote.js'))
        refute_match(regex, %q(import /missing-open-double-quote.js"))
        refute_match(regex, %q(import '/missing-close-single-quote.js))
        refute_match(regex, %q(import "/missing-close-double-quote.js))

        # Escaped and unescaped quotes
        refute_match(regex, %q(import '/unescaped'-single-quote.js'))
        refute_match(regex, %q(import "/unescaped"-double-quote.js"))
        refute_match(regex, %q(import '/unescaped\\\\'-single-quote.js'))
        refute_match(regex, %q(import "/unescaped\\\\"-double-quote.js"))
        refute_match(regex, %q(import '/escaped\\'-single-quote.js'))
        refute_match(regex, %q(import '/escaped\\\\\\'-single-quote.js'))
        refute_match(regex, %q(import "/escaped\\"-double-quote.js"))
        refute_match(regex, %q(import "/escaped\\\\\\"-double-quote.js"))
      end
    end
  end

  ##########################################################################################################
  ## Helpers                                                                                              ##
  ##########################################################################################################

  def import_path(content)
    content.match(Darkroom::JavaScriptDelegate.regex(:import))&.[](:path)
  end
end
