# frozen_string_literal: true

require_relative "../base/text"
require_relative "num"

module Callmend
  module Json
    Repair = Struct.new(:line, :col, :code, :message)
    Result = Struct.new(:value, :repairs)

    class ParseError < StandardError
      attr_reader :line, :col

      def initialize(line, col, message)
        @line = line
        @col = col
        super(message)
      end
    end

    class Parser
      NOT_FOUND = "no JSON object or array found"
      DROP = Object.new.freeze
      private_constant :DROP

      MESSAGES = {
        "R01" => "code fence removed",
        "R02" => "text before the value skipped",
        "R03" => "text after the value ignored",
        "R04" => "comment removed",
        "R05" => "single-quoted string converted",
        "R06" => "unquoted key quoted",
        "R07" => "trailing comma removed",
        "R08" => "missing comma added",
        "R09" => "invalid escape fixed",
        "R10" => "raw control character escaped",
        "R11" => "number normalized",
        "R12" => "literal converted",
        "R13" => "truncated input completed"
      }.freeze

      def self.parse(text)
        new(text).parse
      end

      def initialize(text)
        @chars = text.chars
        @positions = [[1, 1]]
        @chars.each do |character|
          line, col = @positions.last
          @positions << (character.ord == 10 ? [line + 1, 1] : [line, col + 1])
        end
        @repairs = []
        @i = 0
        @fenced = false
        @truncated = false
      end

      def parse
        @i = extraction_start
        value = parse_value
        unless @truncated
          skip_trivia(false)
          consume_closing_fence
          skip_trivia(false)
          repair("R03", @i) if @i < @chars.length
        end
        repair("R13", @chars.length) if @truncated
        Result.new(value, @repairs)
      end

      private

      def extraction_start
        start = @chars[0]&.ord == 0xfeff ? 1 : 0
        first = start
        first += 1 while whitespace?(@chars[first])
        if fence_at?(first)
          @fenced = true
          repair("R01", first)
          @i = first
          @i += 1 while @i < @chars.length && @chars[@i].ord != 10
          @i += 1 if @chars[@i]&.ord == 10
          content_start = @i
          content_start += 1 while whitespace?(@chars[content_start])
          container = find_container(content_start)
          not_found(content_start) unless container
          repair("R02", content_start) if content_start < container
          return container
        end
        return first if container_start?(@chars[first])

        container = find_container(first)
        not_found(first) unless container
        repair("R02", first) if first < @chars.length
        container
      end

      def find_container(index)
        index += 1 while index < @chars.length && !container_start?(@chars[index])
        index < @chars.length ? index : nil
      end

      def not_found(index)
        line, col = location(index)
        raise ParseError.new(line, col, NOT_FOUND)
      end

      def parse_value
        return DROP if eof?

        case current
        when "{" then parse_object
        when "[" then parse_array
        when "\"", "'" then parse_string.first
        when "+", "-", "." then parse_number
        else
          if digit?(current)
            parse_number
          elsif word_start?(current)
            parse_word
          else
            error_at(@i, "unexpected character #{Text.shown(current)}")
          end
        end
      end

      def parse_object
        @i += 1
        object = {}
        loop do
          skip_trivia(true)
          return object if @truncated

          if eof?
            @truncated = true
            return object
          end
          if current == "}"
            @i += 1
            return object
          end
          error_at(@i, "expected a key") if current == ","

          key, complete, pending = parse_key
          unless complete
            discard(pending)
            @truncated = true
            return object
          end
          skip_trivia(true)
          if @truncated || eof?
            discard(pending)
            @truncated = true
            return object
          end
          error_at(@i, "expected ':'") unless current == ":"
          @i += 1
          skip_trivia(true)
          if @truncated || eof?
            discard(pending)
            @truncated = true
            return object
          end
          value = parse_value
          if value.equal?(DROP)
            discard(pending)
            return object
          end
          object[key] = value
          return object if @truncated

          skip_trivia(true)
          return object if @truncated

          if eof?
            @truncated = true
            return object
          end
          if current == "}"
            @i += 1
            return object
          end
          if current == ","
            comma = @i
            @i += 1
            skip_trivia(true)
            return truncation(object) if @truncated || eof?

            if current == "}"
              repair("R07", comma)
              @i += 1
              return object
            end
            next
          end
          if key_start?(current)
            repair("R08", @i)
            next
          end
          error_at(@i, "expected ',' or '}'")
        end
      end

      def parse_array
        @i += 1
        array = []
        loop do
          skip_trivia(true)
          return array if @truncated

          if eof?
            @truncated = true
            return array
          end
          if current == "]"
            @i += 1
            return array
          end
          value = parse_value
          return array if value.equal?(DROP)

          array << value
          return array if @truncated

          skip_trivia(true)
          return array if @truncated

          if eof?
            @truncated = true
            return array
          end
          if current == "]"
            @i += 1
            return array
          end
          if current == ","
            comma = @i
            @i += 1
            skip_trivia(true)
            return truncation(array) if @truncated || eof?

            if current == "]"
              repair("R07", comma)
              @i += 1
              return array
            end
            next
          end
          if value_start?(current)
            repair("R08", @i)
            next
          end
          error_at(@i, "expected ',' or ']'")
        end
      end

      def truncation(value)
        @truncated = true
        value
      end

      def parse_key
        pending = []
        if ["\"", "'"].include?(current)
          key, complete = parse_string(pending)
          [key, complete, pending]
        elsif key_start?(current)
          start = @i
          @i += 1 while word_character?(current)
          key = @chars[start...@i].join
          pending << repair("R06", start)
          [key, true, pending]
        else
          error_at(@i, "expected a key")
        end
      end

      def parse_string(pending = nil)
        quote = current
        pending << repair("R05", @i) if quote == "'" && pending
        repair("R05", @i) if quote == "'" && !pending
        @i += 1
        value = +""
        until eof?
          character = current
          if character == quote
            @i += 1
            return [value, true]
          end
          if character.ord == 92
            slash = @i
            escaped = @chars[@i + 1]
            if escaped.nil?
              @i = @chars.length
              @truncated = true
              return [value, false]
            end
            if escaped == "u"
              return [value, false] unless unicode_escape?(value, slash, quote)

              next
            end
            append_escape(value, escaped, quote, slash)
            next
          end
          repair("R10", @i) if character.ord < 0x20
          value << character
          @i += 1
        end
        @truncated = true
        [value, false]
      end

      def append_escape(value, escaped, quote, slash)
        if escaped == "\""
          value << "\""
        elsif escaped.ord == 92
          value << 92.chr
        elsif escaped == "/"
          value << "/"
        elsif escaped == "b"
          value << 8.chr
        elsif escaped == "f"
          value << 12.chr
        elsif escaped == "n"
          value << 10.chr
        elsif escaped == "r"
          value << 13.chr
        elsif escaped == "t"
          value << 9.chr
        elsif escaped == "'" && quote == "'"
          value << "'"
        else
          repair("R09", slash)
          value << escaped
        end
        @i += 2
      end

      def unicode_escape?(value, slash, _quote)
        start = @i + 2
        digits = @chars[start, 4] || []
        invalid_digit = digits.index { |digit| !hex_digit?(digit) }
        if invalid_digit
          repair("R09", slash)
          value << "u" << digits.take(invalid_digit).join
          @i = start + invalid_digit
          return true
        end
        if digits.length < 4
          @i = @chars.length
          @truncated = true
          return false
        end
        codepoint = digits.join.to_i(16)
        @i = start + 4
        if codepoint.between?(0xd800, 0xdbff)
          low = following_low_surrogate
          if low
            value << (0x10000 + ((codepoint - 0xd800) * 0x400) + low - 0xdc00).chr(Encoding::UTF_8)
            @i += 6
          else
            repair("R09", slash)
            value << 0xfffd.chr(Encoding::UTF_8)
          end
        elsif codepoint.between?(0xdc00, 0xdfff)
          repair("R09", slash)
          value << 0xfffd.chr(Encoding::UTF_8)
        else
          value << codepoint.chr(Encoding::UTF_8)
        end
        true
      end

      def following_low_surrogate
        return nil unless @chars[@i]&.ord == 92 && @chars[@i + 1] == "u"

        digits = @chars[@i + 2, 4]
        return nil unless digits&.length == 4 && digits.all? { |digit| hex_digit?(digit) }

        codepoint = digits.join.to_i(16)
        codepoint if codepoint.between?(0xdc00, 0xdfff)
      end

      def parse_number
        start = @i
        sign = ""
        if ["+", "-"].include?(current)
          sign = current
          @i += 1
          return incomplete_number if eof?
        end
        integer = take_digits
        fraction = nil
        if current == "."
          @i += 1
          fraction = take_digits
        end
        if integer.empty? && (fraction.nil? || fraction.empty?)
          return incomplete_number if eof?

          error_at(start, "unexpected character #{Text.shown(@chars[start])}")
        end
        exponent = nil
        if %w[e E].include?(current)
          exp_start = @i
          cursor = @i + 1
          exp_sign = ""
          if ["+", "-"].include?(@chars[cursor])
            exp_sign = @chars[cursor]
            cursor += 1
          end
          return incomplete_number if cursor >= @chars.length

          digits_start = cursor
          cursor += 1 while digit?(@chars[cursor])
          if cursor > digits_start
            digits = @chars[digits_start...cursor].join
            error_at(start, "number out of range") if digits.length > 3
            exponent = [exp_sign, digits]
            @i = cursor
          else
            @i = exp_start
          end
        end
        normalized = normalize_number(sign, integer, fraction, exponent)
        original = @chars[start...@i].join
        repair("R11", start) if normalized != original
        Num.new(normalized)
      end

      def incomplete_number
        @i = @chars.length
        @truncated = true
        DROP
      end

      def take_digits
        start = @i
        @i += 1 while digit?(current)
        @chars[start...@i].join
      end

      def normalize_number(sign, integer, fraction, exponent)
        integer = integer.sub(/\A0+(?=[0-9])/, "")
        integer = "0" if integer.empty?
        result = (sign == "-" ? "-" : "") + integer
        result += ".#{fraction}" if fraction && !fraction.empty?
        if exponent
          exp_sign, digits = exponent
          result += "e#{"-" if exp_sign == "-"}#{digits}"
        end
        result
      end

      def parse_word
        start = @i
        @i += 1 while word_character?(current)
        word = @chars[start...@i].join
        return true if word == "true"
        return false if word == "false"
        return nil if word == "null"
        return converted_literal(start, true) if word == "True"
        return converted_literal(start, false) if word == "False"
        return converted_literal(start, nil) if word == "None"

        if eof? && %w[true false null True False None].any? { |literal| literal.start_with?(word) && literal != word }
          @truncated = true
          return DROP
        end
        error_at(start, "unexpected word #{Text.shown(word)}")
      end

      def converted_literal(start, value)
        repair("R12", start)
        value
      end

      def skip_trivia(in_container)
        loop do
          @i += 1 while whitespace?(current)
          return if eof?

          if current == "/" && @chars[@i + 1] == "/"
            repair("R04", @i)
            @i += 2
            @i += 1 while !eof? && @chars[@i].ord != 10
          elsif current == "/" && @chars[@i + 1] == "*"
            repair("R04", @i)
            @i += 2
            @i += 1 while @i + 1 < @chars.length && !(@chars[@i] == "*" && @chars[@i + 1] == "/")
            if @i + 1 >= @chars.length
              @i = @chars.length
              @truncated = true if in_container
              return
            end
            @i += 2
          elsif current == "/" && @chars[@i + 1].nil? && in_container
            @i = @chars.length
            @truncated = true
            return
          else
            return
          end
        end
      end

      def consume_closing_fence
        return unless @fenced && fence_line_at?(@i)

        @i += 3
        @i += 1 while horizontal_whitespace?(current)
        @i += 1 if @chars[@i]&.ord == 10
      end

      def fence_line_at?(index)
        line_start = index
        line_start -= 1 while line_start.positive? && @chars[line_start - 1].ord != 10
        return false unless @chars[line_start...index].all? { |character| horizontal_whitespace?(character) }
        return false unless @chars[index, 3] == ["`", "`", "`"]

        cursor = index + 3
        cursor += 1 while horizontal_whitespace?(@chars[cursor])
        @chars[cursor].nil? || @chars[cursor].ord == 10
      end

      def repair(code, index)
        line, col = location(index)
        item = Repair.new(line, col, code, MESSAGES.fetch(code))
        @repairs << item
        item
      end

      def discard(items)
        items.each do |item|
          index = @repairs.index { |existing| existing.equal?(item) }
          @repairs.delete_at(index) if index
        end
      end

      def error_at(index, message)
        line, col = location(index)
        raise ParseError.new(line, col, message)
      end

      def location(index)
        @positions[index] || @positions.last
      end

      def eof?
        @i >= @chars.length
      end

      def current
        @chars[@i]
      end

      def whitespace?(character)
        [32, 9, 13, 10].include?(character&.ord)
      end

      def horizontal_whitespace?(character)
        [32, 9, 13].include?(character&.ord)
      end

      def container_start?(character)
        ["{", "["].include?(character)
      end

      def fence_at?(index)
        @chars[index, 3] == ["`", "`", "`"]
      end

      def key_start?(character)
        character == "\"" || character == "'" || letter?(character) || character == "_"
      end

      def value_start?(character)
        container_start?(character) || character == "\"" || character == "'" ||
          ["+", "-", "."].include?(character) || digit?(character) || word_start?(character)
      end

      def word_start?(character)
        letter?(character) || character == "_"
      end

      def word_character?(character)
        word_start?(character) || digit?(character)
      end

      def letter?(character)
        character && (character.ord.between?(65, 90) || character.ord.between?(97, 122))
      end

      def digit?(character)
        character && character.ord >= 48 && character.ord <= 57
      end

      def hex_digit?(character)
        digit?(character) || (character && character.ord >= 65 && character.ord <= 70) ||
          (character && character.ord >= 97 && character.ord <= 102)
      end
    end
  end
end
