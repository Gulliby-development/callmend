# frozen_string_literal: true

module Callmend
  module Text
    module_function

    def plural(count, word)
      "#{count} #{word}#{"s" unless count == 1}"
    end

    def shown(text)
      escaped = text.chars.map do |character|
        case character
        when "\""
          "\\\""
        when "\\"
          "\\\\"
        else
          codepoint = character.ord
          if codepoint < 0x20 || codepoint == 0x7f
            "\\x#{codepoint.to_s(16).rjust(2, "0")}"
          else
            character
          end
        end
      end.join

      "\"#{escaped}\""
    end

    def lines(list)
      return "" if list.empty?

      "#{list.join("\n")}\n"
    end
  end
end
