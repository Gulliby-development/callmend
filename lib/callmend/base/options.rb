# frozen_string_literal: true

require_relative "failure"

module Callmend
  Options = Struct.new(:flags, :settings, :operands) do
    def flag?(name)
      flags.include?(name)
    end

    def self.parse(args, spec)
      flags = []
      settings = {}
      operands = []
      options_ended = false
      index = 0

      while index < args.length
        argument = args[index]

        if argument == "--" && !options_ended
          options_ended = true
        elsif options_ended || argument == "-" || !argument.start_with?("-")
          operands << argument
        else
          name, attached_value = argument.split("=", 2)
          kind = spec[name]
          raise Failure.new(2, "unknown option #{name}") unless kind

          case kind
          when "flag"
            raise Failure.new(2, "option #{name} takes no value") unless attached_value.nil?

            flags << name unless flags.include?(name)
          when "value"
            if attached_value.nil?
              index += 1
              raise Failure.new(2, "option #{name} needs a value") if index >= args.length

              attached_value = args[index]
            end
            raise Failure.new(2, "option #{name} needs a non-empty value") if attached_value.empty?

            settings[name] = attached_value
          end
        end

        index += 1
      end

      new(flags, settings, operands)
    end
  end
end
