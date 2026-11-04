# frozen_string_literal: true

require_relative "num"

module Callmend
  module Json
    module Writer
      module_function

      def dump(value, pretty: false, width: 2, sort_keys: false)
        render(value, pretty, 0, width, sort_keys)
      end

      def quote(text)
        quoted = +"\""
        text.each_codepoint do |codepoint|
          quoted << case codepoint
                    when 0x22 then "\\\""
                    when 0x5c then "\\\\"
                    when 0x08 then "\\b"
                    when 0x0c then "\\f"
                    when 0x0a then "\\n"
                    when 0x0d then "\\r"
                    when 0x09 then "\\t"
                    when 0x00..0x1f then format("\\u%04x", codepoint)
                    else codepoint
                    end
        end
        quoted << "\""
      end

      def render(value, pretty, depth, width, sort_keys)
        case value
        when NilClass then "null"
        when TrueClass then "true"
        when FalseClass then "false"
        when String then quote(value)
        when Num then value.text
        when Array then render_array(value, pretty, depth, width, sort_keys)
        when Hash then render_hash(value, pretty, depth, width, sort_keys)
        else raise TypeError, "unsupported JSON value: #{value.class}"
        end
      end
      private_class_method :render

      def render_array(values, pretty, depth, width, sort_keys)
        return "[]" if values.empty?

        if pretty
          contents = values.map do |value|
            "#{indent(depth + 1, width)}#{render(value, true, depth + 1, width, sort_keys)}"
          end.join(",\n")
          "[\n#{contents}\n#{indent(depth, width)}]"
        else
          "[#{values.map { |value| render(value, false, depth + 1, width, sort_keys) }.join(",")}]"
        end
      end
      private_class_method :render_array

      def render_hash(values, pretty, depth, width, sort_keys)
        return "{}" if values.empty?

        members = sort_keys ? values.sort_by { |key, _value| key } : values.to_a
        if pretty
          contents = members.map do |key, value|
            "#{indent(depth + 1, width)}#{quote(key)}: #{render(value, true, depth + 1, width, sort_keys)}"
          end.join(",\n")
          "{\n#{contents}\n#{indent(depth, width)}}"
        else
          contents = members.map { |key, value| "#{quote(key)}:#{render(value, false, depth + 1, width, sort_keys)}" }
          "{#{contents.join(",")}}"
        end
      end
      private_class_method :render_hash

      def indent(depth, width)
        " " * (width * depth)
      end
      private_class_method :indent
    end
  end
end
