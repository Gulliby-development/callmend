# frozen_string_literal: true

require_relative "../base/failure"
require_relative "../base/inputs"
require_relative "../base/text"
require_relative "../json/parser"
require_relative "../schema/validator"

module Callmend
  module Cmd
    module CheckCommand
      module_function

      def load_schema(path, inputs)
        name = Inputs.display_name(path)
        text = inputs.text(path)
        result = Json::Parser.parse(text)
        return result.value if result.value.is_a?(Hash)

        raise Failure.new(2, "#{name}: the schema must be a JSON object")
      rescue Json::ParseError => e
        raise Failure.new(2, "#{name}:#{e.line}:#{e.col}: #{e.message}")
      end

      def run(options, inputs, out)
        schema_path, data_path = options.operands
        raise Failure.new(2, "check needs a schema file and a file") unless options.operands.length == 2

        schema = load_schema(schema_path, inputs)
        data_text = inputs.text(data_path)
        check_data(data_text, schema, out)
      end

      def check_data(data_text, schema, out)
        result = Json::Parser.parse(data_text)
        problems = Schema::Validator.problems(schema, result.value)
        if problems.empty?
          out.write_out("ok\n")
          0
        else
          lines = problems.map { |path, message| "#{path}: #{message}" }
          lines << Text.plural(problems.length, "problem")
          out.write_out(Text.lines(lines))
          1
        end
      rescue Json::ParseError => e
        out.write_out("error: #{e.line}:#{e.col}: #{e.message}\n")
        1
      end
    end
  end
end
