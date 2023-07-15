# frozen_string_literal: true

require('darkroom')
require('minitest/autorun')
require_relative('test_helper')

class JavaScriptDelegateTest < Minitest::Test
  include(TestHelper)

  IIFE_PREFIX = <<~EOS
    ((...bundle) => {
      const modules = {}
      const setters = []
      const $import = (name, setter) =>
        modules[name] ? setter(modules[name]) : setters.push([setter, name])

      for (const [name, def] of bundle)
        modules[name] = def($import)

      for (const [setter, name] of setters)
        setter(modules[name])
    })(
  EOS

  context(Darkroom::JavaScriptDelegate) do
    ########################################################################################################
    ## ::regex(:import)                                                                                   ##
    ########################################################################################################

    context('::regex(:import)') do
      test('matches import statements with proper syntax') do
        import_regex = Darkroom::JavaScriptDelegate.regex(:import)
        assert_kind_of(Regexp, import_regex)

        starts = ['', '  ', ';', ';  ', '}', '}  ']
        whitespaces = ['  ', "  \n  "]
        defaults = [nil, 'MyDefault']
        modules = [nil, 'MyModule']
        names = [
          nil,
          [['Exp']],
          [['Exp', 'Imp']],
          [['"Nasty} from \'/app.js\';"', 'Imp']],
          [['Exp1', 'Imp1'], ['Exp2', 'Imp2']],
        ]
        quotes = ['\'', '"']
        finishes = [';', '  ;', "\n", ";\n", ";  \n"]

        starts.each { |start| whitespaces.each { |ws| defaults.each { |default| modules.each { |mod|
        names.each { |names| quotes.each { |quote| finishes.each { |finish|
          if !mod && names
            named = names.map { |exp, imp| "#{exp}#{"#{ws}as#{ws}#{imp}" if imp}" }.join("#{ws},#{ws}")
          end

          statement =
            "#{start}#{ws}import#{ws}"\
            "#{default}"\
            "#{"#{ws},#{ws}" if default && (mod || named)}"\
            "#{"*#{ws}as#{ws}#{mod}" if mod}"\
            "#{"{#{named}}" if named}"\
            "#{"#{ws}from#{ws}" if default || mod || named}"\
            "#{quote}/app.js#{quote}#{finish}"
          match = statement.match(import_regex)

          assert(match, "Expected #{statement.inspect} to match import regex")

          if default
            assert_equal(default, match[:default], "Incorrect :default capture for #{statement.inspect}")
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
        }}}}}}}
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
  end


  ########################################################################################################
  ## ::regex(:import)                                                                                   ##
  ########################################################################################################

  context(Darkroom::Asset, '#process') do
    test('concatenates JavaScript side-effect imports when IIFE are not enabled') do
      import = new_asset('/import.js', "console.log('Import')\n")
      asset = new_asset('/app.js', "import '/import.js'\n\nconsole.log('App')\n")
      processed = <<~EOS
        console.log('Import')

        console.log('App')
      EOS

      asset.process

      refute_error(asset.errors)
      assert_equal(processed, asset.content)
    end

    test('concatenates JavaScript named imports when IIFE are not enabled') do
      import = new_asset('/import.js', "export function Import() { console.log('Import') }\n")
      asset = new_asset('/app.js', "import {Import} from '/import.js'\n\nconsole.log('App')\n")
      processed = <<~EOS
        function Import() { console.log('Import') }

        console.log('App')
      EOS

      asset.process

      refute_error(asset.errors)
      assert_equal(processed, asset.content)
    end

    test('generates IIFE for JavaScript assets with no imports when IIFE are enabled') do
      Darkroom.javascript_iife = true

      asset = new_asset('/app.js', "console.log('App')\n")
      processed = <<~EOS
        #{IIFE_PREFIX}
        ['/app.js', $import => {

        console.log('App')

        return Object.seal({})

        }],

        )
      EOS

      asset.process

      refute_error(asset.errors)
      assert_equal(processed, asset.content)
    ensure
      Darkroom.javascript_iife = false
    end

    test('generates IIFE for JavaScript assets with side-effect imports when IIFE are enabled') do
      Darkroom.javascript_iife = true

      import = new_asset('/import.js', "console.log('Import')\n")
      asset = new_asset('/app.js', "import '/import.js'\n\nconsole.log('App')\n")
      processed = <<~EOS
        #{IIFE_PREFIX}
        ['/import.js', $import => {

        console.log('Import')

        return Object.seal({})

        }],

        ['/app.js', $import => {


        console.log('App')

        return Object.seal({})

        }],

        )
      EOS

      asset.process

      refute_error(asset.errors)
      assert_equal(processed, asset.content)
    ensure
      Darkroom.javascript_iife = false
    end

    test('generates IIFE for JavaScript assets with named imports when IIFE are enabled') do
      Darkroom.javascript_iife = true

      default = new_asset('/default.js', "export default function Default() { console.log('Default') }\n")
      named = new_asset('/named.js', "export function Named() { console.log('Named') }\n")
      aliased = new_asset('/aliased.js', "function Aliased() { console.log('Aliased') }\nexport {Aliased "\
        "as 'Something Else', Aliased as 'Another'}\n")

      asset = new_asset('/app.js',
        <<~EOS
          import Default from '/default.js'
          import {Import} from '/named.js'
          import {Aliased as Renamed} from '/aliased.js'

          console.log('App')
        EOS
      )

      processed = <<~EOS
        #{IIFE_PREFIX}
        ['/default.js', $import => {

        function Default() { console.log('Default') }

        return Object.seal({
          default: Default,
        })

        }],

        ['/named.js', $import => {

        function Named() { console.log('Named') }

        return Object.seal({
          Named: Named,
        })

        }],

        ['/aliased.js', $import => {

        function Aliased() { console.log('Aliased') }

        return Object.seal({
          'Something Else': Aliased,
          'Another': Aliased,
        })

        }],

        ['/app.js', $import => {

        let Renamed; $import('/aliased.js', m => Renamed = m.Aliased)
        let Import; $import('/named.js', m => Import = m.Import)
        let Default; $import('/default.js', m => Default = m.default)

        console.log('App')

        return Object.seal({})

        }],

        )
      EOS

      asset.process

      refute_error(asset.errors)
      assert_equal(processed, asset.content)
    ensure
      Darkroom.javascript_iife = false
    end
  end
end
