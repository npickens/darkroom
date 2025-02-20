# frozen_string_literal: true

require('strscan')
require_relative('../asset')
require_relative('../delegate')

class Darkroom
  # Delegate for handling JavaScript-specific asset processing.
  class JavaScriptDelegate < Delegate
    IDENTIFIER_REGEX = /[_$a-zA-Z][_$a-zA-Z0-9]*/
    COMMA_REGEX = /,/
    QUOTED_REGEX = /
      (?<quoted>
        (?<quote>['"])(?:
          (?<=[^\\])\\(?:\\\\)*\k<quote> |
          (?!\k<quote>).
        )*\k<quote>
      )
    /x

    content_type('text/javascript')

    ########################################################################################################
    ## Imports                                                                                            ##
    ########################################################################################################

    IMPORT_REGEX = /
      (?<=^|;|})[^\S\n]*
      import\s+(
        ((?<default>#{IDENTIFIER_REGEX.source})(?:\s*,\s*|(?=\s+from\s+)))?
        (
          \*\s+as\s+(?<module>#{IDENTIFIER_REGEX.source}) |
          \{(?<named>[\s\S]+?)\}
        )?
        \s+from\s+
      )?#{Asset::QUOTED_PATH_REGEX.source}
      [^\S\n]*;?[^\S\n]*(\n|\Z)
    /x

    IMPORT_ITEM_REGEX = /
      \s*
      (?<name>#{IDENTIFIER_REGEX.source}|#{QUOTED_REGEX.source}(?=\s+as\s+))
      (\s+as\s+(?<alias>#{IDENTIFIER_REGEX.source}))?
      \s*
    /x

    import(IMPORT_REGEX) do |parse_data:, match:, asset:|
      items = []
      items << [match[:default], '.default'] if match[:default]
      items << [match[:module], ''] if match[:module]

      if match[:named]
        scanner = StringScanner.new(match[:named])

        while scanner.scan(IMPORT_ITEM_REGEX)
          items << [
            scanner[:alias] || scanner[:name],
            scanner[:quote] ? "[#{scanner[:name]}]" : ".#{scanner[:name]}"
          ]

          break unless scanner.scan(COMMA_REGEX)
        end

        error('Invalid import statement') unless scanner.eos?
      end

      ((parse_data[:imports] ||= {})[asset.path] ||= []).concat(items) unless items.empty?

      ''
    end

    ########################################################################################################
    ## Exports                                                                                            ##
    ########################################################################################################

    EXPORT_REGEX = /
      (?<=^|;|})[^\S\n]*
      export\s+(
        (?<default>default\s+)?
        (?<keep>(let|const|var|function\*?|class)\s+(?<name>#{IDENTIFIER_REGEX.source}))
      |
        \{(?<named>.+?)\}
        [^\S\n]*;?[^\S\n]*(\n|\Z)
      )
    /x

    EXPORT_ITEM_REGEX = /
      \s*
      (?<name>#{IDENTIFIER_REGEX.source})
      (\s+as\s+(?<alias>#{IDENTIFIER_REGEX.source}|#{QUOTED_REGEX.source}))?
      \s*
    /x

    parse(:export, EXPORT_REGEX) do |parse_data:, match:|
      items = (parse_data[:exports] ||= [])

      if match[:default]
        items << ['default', match[:name]]
      elsif match[:name]
        items << [match[:name], match[:name]]
      else
        scanner = StringScanner.new(match[:named])

        while scanner.scan(EXPORT_ITEM_REGEX)
          items << [scanner[:alias] || scanner[:name], scanner[:name]]

          break if scanner.eos?
          break unless scanner.scan(COMMA_REGEX)
        end

        error('Invalid export statement') unless scanner.eos?
      end

      match[:keep]
    end

    ########################################################################################################
    ## Compile                                                                                            ##
    ########################################################################################################

    compile do |parse_data:, path:, own_content:|
      next unless Darkroom.javascript_iife

      (parse_data[:imports] || []).reverse_each do |import_path, items|
        mod_suffix = nil
        prefix = '{ ' if items.size != 1
        suffix = ' }' if items.size != 1

        begin
          mod = "m#{mod_suffix}"
          mod_suffix = (mod_suffix || 1) + 1
        end while items.any? { |i| i.first == mod }

        own_content.prepend(
          "let #{items.map(&:first).join(', ')}; " \
          "$import('#{import_path}', " \
          "#{mod} => #{prefix}#{items.map { |(i, e)| "#{i} = #{mod}#{e}" }.join(', ')}#{suffix})\n"
        )
      end

      own_content.prepend("['#{path}', $import => {\n\n")
      own_content << <<~JS

        return Object.seal({#{
          if parse_data[:exports] && !parse_data[:exports].empty?
            "\n#{parse_data[:exports].map { |k, v| "  #{k}: #{v},\n" }.join}"
          end
        }})

        }],
      JS
    end

    ########################################################################################################
    ## Finalize                                                                                           ##
    ########################################################################################################

    finalize do |parse_data:, path:, content:|
      next unless Darkroom.javascript_iife

      (content.frozen? ? content.dup : content).prepend(
        <<~JS
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

        JS
      ) << "\n)\n"
    end

    ########################################################################################################
    ## Minify                                                                                             ##
    ########################################################################################################

    minify(lib: 'terser') do |parse_data:, path:, content:|
      Terser.compile(content)
    end
  end
end
