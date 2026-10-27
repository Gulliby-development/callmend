# frozen_string_literal: true

require_relative "../base/failure"
require_relative "../base/inputs"
require_relative "../json/parser"
require_relative "../json/writer"

module Callmend
  module Cmd
    module RepairCommand
      module_function

      def run(options, inputs, out)
        raise Failure.new(2, "repair needs exactly one file") unless options.operands.length == 1

        path = options.operands.first
        begin
          result = Json::Parser.parse(inputs.text(path))
        rescue Json::ParseError => e
          name = Inputs.display_name(path)
          raise Failure.new(1, "#{name}:#{e.line}:#{e.col}: #{e.message}")
        end

        strict = options.flag?("--strict")
        repaired = !result.repairs.empty?
        if options.flag?("--report") || (strict && repaired)
          name = Inputs.display_name(path)
          result.repairs.each do |repair|
            out.write_err("#{name}:#{repair.line}:#{repair.col}: #{repair.code} #{repair.message}\n")
          end
        end

        return 1 if strict && repaired

        pretty = options.flag?("--pretty")
        out.write_out("#{Json::Writer.dump(result.value, pretty: pretty)}\n")
        0
      end
    end
  end
end
