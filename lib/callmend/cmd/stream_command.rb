# frozen_string_literal: true

require_relative "../base/failure"
require_relative "../base/inputs"
require_relative "../json/parser"
require_relative "../json/writer"

module Callmend
  module Cmd
    module StreamCommand
      module_function

      def run(options, inputs, out)
        raise Failure.new(2, "stream needs exactly one file") unless options.operands.length == 1

        path = options.operands.first
        cumulative = +""
        chunk_number = 0

        inputs.text(path).each_line.with_index(1) do |physical_line, line_number|
          chunk = trim_chunk_line(physical_line)
          next if chunk.empty?

          decoded = decode_chunk(chunk, path, line_number)
          invalid_chunk!(path, line_number) unless decoded

          chunk_number += 1
          cumulative << decoded
          out.write_out(snapshot(chunk_number, cumulative))
        end

        0
      end

      def trim_chunk_line(physical_line)
        physical_line.delete_suffix("\n").sub(/[ \t]*\r?[ \t]*\z/, "").sub(/\A[ \t]*/, "")
      end
      private_class_method :trim_chunk_line

      def decode_chunk(chunk, path, line_number)
        result = Json::Parser.parse("[#{chunk}]")
        return unless result.repairs.empty?
        return unless result.value.is_a?(Array) && result.value.length == 1

        result.value.first if result.value.first.is_a?(String)
      rescue Json::ParseError => e
        invalid_chunk!(path, line_number, e)
      end
      private_class_method :decode_chunk

      def invalid_chunk!(path, line_number, cause = nil)
        name = Inputs.display_name(path)
        failure = Failure.new(2, "#{name}:#{line_number}: invalid chunk (expected a JSON string)")
        raise failure, cause: cause
      end
      private_class_method :invalid_chunk!

      def snapshot(chunk_number, cumulative)
        result = Json::Parser.parse(cumulative)
        value = Json::Writer.dump(result.value)
        "chunk #{chunk_number}: #{value}\n"
      rescue Json::ParseError => e
        value = if e.message == Json::Parser::NOT_FOUND
                  "(no value)"
                else
                  "error: #{e.line}:#{e.col}: #{e.message}"
                end
        "chunk #{chunk_number}: #{value}\n"
      end
      private_class_method :snapshot
    end
  end
end
