# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('test_helper')

class JavaScriptDelegateTest < Minitest::Test
  include(TestHelper)

  ##########################################################################################################
  ## Import Regex                                                                                         ##
  ##########################################################################################################

  test('matches import statements with proper syntax') do
    import_regex = Darkroom::JavaScriptDelegate.regex(:import)

    assert_kind_of(Regexp, import_regex)

    starts = ['', '  ', ';', ';  ', '}', '}  ']
    whitespaces = ['  ', "  \n  "]
    defaults = [nil, 'MyDefault']
    modules = [nil, 'MyModule']
    exports_imports = [
      nil,
      [%w[Exp]],
      [%w[Exp Imp]],
      [['"Nasty} from \'/app.js\';"', 'Imp']],
      [%w[Exp1 Imp1], %w[Exp2 Imp2]],
    ]
    quotes = ['\'', '"']
    finishes = [';', '  ;', "\n", ";\n", ";  \n"]

    starts.each do |start|
      whitespaces.each do |whitespace|
        defaults.each do |default|
          modules.each do |mod|
            exports_imports.each do |export_import|
              quotes.each do |quote|
                finishes.each do |finish|
                  if !mod && export_import
                    named = export_import.map do |export, import|
                      "#{export}#{"#{whitespace}as#{whitespace}#{import}" if import}"
                    end.join("#{whitespace},#{whitespace}")
                  end

                  statement =
                    "#{start}#{whitespace}import#{whitespace}" \
                    "#{default}" \
                    "#{"#{whitespace},#{whitespace}" if default && (mod || named)}" \
                    "#{"*#{whitespace}as#{whitespace}#{mod}" if mod}" \
                    "#{"{#{named}}" if named}" \
                    "#{"#{whitespace}from#{whitespace}" if default || mod || named}" \
                    "#{quote}/app.js#{quote}#{finish}"
                  match = statement.match(import_regex)

                  assert(match, "Expected #{statement.inspect} to match import regex")

                  if default
                    assert_equal(default, match[:default], 'Incorrect :default capture for ' \
                      "#{statement.inspect}")
                  else
                    assert_nil(default, "Incorrect :default capture for #{statement.inspect}")
                  end

                  if mod && !named
                    assert_equal(mod, match[:module], "Incorrect :module capture for #{statement.inspect}")
                  elsif named && !mod
                    assert_equal(named, match[:named], "Incorrect :named capture for #{statement.inspect}")
                  end

                  assert_nil(mod, "Incorrect :module capture for #{statement.inspect}.") if !mod || named
                  assert_nil(named, "Incorrect :named capture for #{statement.inspect}.") if !named || mod

                  assert_equal('/app.js', match[:path], "Incorrect :path capture for #{statement.inspect}")
                end
              end
            end
          end
        end
      end
    end
  end

  test('does not match import statements with bad syntax') do
    regex = Darkroom::JavaScriptDelegate.regex(:import)

    [
      '',
      '* as ModuleBeforeDefault, MyDefault',
      '* as MyModule, {NamedWithModule}',
      'MyDefault, * as MyModule, {NamedWithModule}',
      '{NamedFirst}, MyDefault',
      '{NamedFirst}, * as MyModule',
      '{NamedFirst}, MyDefault, * as MyModule',
      '{NamedFirst}, * as MyModule, MyDefault',
    ].each do |bad|
      bad += ' from ' unless bad.empty?

      [
        # Good quoting
        (%Q(import #{bad}'/app.js') unless bad.empty?),

        # Bad quoting
        %Q(import #{bad}/no-quotes.js),
        %Q(import #{bad}"/mismatched-quotes.js'),
        %Q(import #{bad}'/mismatched-quotes.js"),
        %Q(import #{bad}/missing-open-single-quote.js'),
        %Q(import #{bad}/missing-open-double-quote.js"),
        %Q(import #{bad}'/missing-close-single-quote.js),
        %Q(import #{bad}"/missing-close-double-quote.js),

        # Escaped and unescaped quotes
        %Q(import #{bad}'/unescaped'-single-quote.js'),
        %Q(import #{bad}"/unescaped"-double-quote.js"),
        %Q(import #{bad}'/unescaped\\\\'-single-quote.js'),
        %Q(import #{bad}"/unescaped\\\\"-double-quote.js"),
        %Q(import #{bad}'/escaped\\'-single-quote.js'),
        %Q(import #{bad}'/escaped\\\\\\'-single-quote.js'),
        %Q(import #{bad}"/escaped\\"-double-quote.js"),
        %Q(import #{bad}"/escaped\\\\\\"-double-quote.js"),
      ].each do |statement|
        next if statement.nil?

        match = statement.match(regex)

        refute(match, "Expected #{statement.inspect} to not match import regex")
      end
    end
  end
end
