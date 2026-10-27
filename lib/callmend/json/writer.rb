# frozen_string_literal: true

require_relative "num"

module Callmend
  module Json
    module Writer
      module_function

      def dump(value, pretty: false)
        render(value, pretty, 0)
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

      def render(value, pretty, depth)
        case value
        when NilClass then "null"
        when TrueClass then "true"
        when FalseClass then "false"
        when String then quote(value)
        when Num then value.text
        when Array then render_array(value, pretty, depth)
        when Hash then render_hash(value, pretty, depth)
        else raise TypeError, "unsupported JSON value: #{value.class}"
        end
      end
      private_class_method :render

      def render_array(values, pretty, depth)
        return "[]" if values.empty?

        if pretty
          contents = values.map do |value|
            "#{indent(depth + 1)}#{render(value, true, depth + 1)}"
          end.join(",\n")
          "[\n#{contents}\n#{indent(depth)}]"
        else
          "[#{values.map { |value| render(value, false, depth + 1) }.join(",")}]"
        end
      end
      private_class_method :render_array

      def render_hash(values, pretty, depth)
        return "{}" if values.empty?

        if pretty
          contents = values.map do |key, value|
            "#{indent(depth + 1)}#{quote(key)}: #{render(value, true, depth + 1)}"
          end.join(",\n")
          "{\n#{contents}\n#{indent(depth)}}"
        else
          contents = values.map { |key, value| "#{quote(key)}:#{render(value, false, depth + 1)}" }
          "{#{contents.join(",")}}"
        end
      end
      private_class_method :render_hash

      def indent(depth)
        "  " * depth
      end
      private_class_method :indent
    end
  end
end
