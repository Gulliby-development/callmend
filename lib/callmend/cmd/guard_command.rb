# frozen_string_literal: true

require_relative "../base/failure"
require_relative "../base/inputs"
require_relative "../cmd/check_command"
require_relative "../guard/scripted"
require_relative "../guard/loop"

module Callmend
  module Cmd
    module GuardCommand
      module_function

      def run(options, inputs, out)
        schema_path = options.settings["--schema"]
        raise Failure.new(2, "guard needs --schema") unless schema_path

        max_tries_text = options.settings.fetch("--max-tries", "3")
        unless /\A[0-9]{1,2}\z/.match?(max_tries_text) && max_tries_text.to_i.positive?
          raise Failure.new(2, "invalid --max-tries value: #{max_tries_text}")
        end

        raise Failure.new(2, "guard needs exactly one script file") unless options.operands.length == 1

        schema = CheckCommand.load_schema(schema_path, inputs)
        script = inputs.text(options.operands.first)
        provider = Guard::Scripted.new(script)
        outcome = Guard::Loop.run(provider, schema, max_tries_text.to_i)
        out.write_out(outcome.text)
        outcome.code
      end
    end
  end
end
