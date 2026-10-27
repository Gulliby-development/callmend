# frozen_string_literal: true

require_relative "../base/failure"
require_relative "../base/options"
require_relative "repair_command"
require_relative "stream_command"
require_relative "check_command"
require_relative "guard_command"

module Callmend
  module Cmd
    module Cli
      USAGE = <<~TEXT
        usage: callmend repair [--pretty] [--report] [--strict] FILE
               callmend stream FILE
               callmend check SCHEMA FILE
               callmend guard --schema SCHEMA [--max-tries N] SCRIPT
      TEXT

      module_function

      def run(args, inputs, out)
        if args.empty?
          out.write_err(USAGE)
          return 2
        end

        return help(out) if ["--help", "-h"].include?(args.first)

        command = args.first
        adapter = adapter_for(command)
        options = Options.parse(args.drop(1), option_spec(command))
        adapter.run(options, inputs, out)
      rescue Failure => e
        out.write_err("callmend: #{e.message}\n")
        e.exit_code
      end

      def help(out)
        out.write_out(USAGE)
        0
      end
      private_class_method :help

      def adapter_for(command)
        case command
        when "repair"
          RepairCommand
        when "stream"
          StreamCommand
        when "check"
          CheckCommand
        when "guard"
          GuardCommand
        else
          raise Failure.new(2, "unknown command #{command}")
        end
      end
      private_class_method :adapter_for

      def option_spec(command)
        case command
        when "repair"
          { "--pretty" => "flag", "--report" => "flag", "--strict" => "flag" }
        when "guard"
          { "--schema" => "value", "--max-tries" => "value" }
        else
          {}
        end
      end
      private_class_method :option_spec
    end
  end
end
