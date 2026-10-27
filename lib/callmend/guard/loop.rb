# frozen_string_literal: true

require_relative "../base/text"
require_relative "../json/parser"
require_relative "../json/writer"
require_relative "../schema/validator"
require_relative "feedback"

module Callmend
  module Guard
    Outcome = Struct.new(:text, :code)

    module Loop
      module_function

      def run(provider, schema, max_tries)
        messages = []
        transcript = []

        1.upto(max_tries) do |attempt|
          reply = provider.next_reply(messages)
          if reply.nil?
            transcript << "attempt #{attempt}: no reply left in the script"
            return Outcome.new(Text.lines(transcript), 1)
          end

          begin
            result = Json::Parser.parse(reply)
            problems = Schema::Validator.problems(schema, result.value)
            if problems.empty?
              repairs = result.repairs.length
              repair_note = repairs.zero? ? "" : " (#{Text.plural(repairs, "repair")})"
              transcript << "attempt #{attempt}: ok#{repair_note}"
              transcript << Json::Writer.dump(result.value)
              return Outcome.new(Text.lines(transcript), 0)
            end
          rescue Json::ParseError => e
            problems = [["$", "invalid JSON: #{e.line}:#{e.col}: #{e.message}"]]
          end

          transcript << "attempt #{attempt}: #{Text.plural(problems.length, "problem")}"
          transcript.concat(problems.map { |path, message| "  #{path}: #{message}" })

          if attempt < max_tries
            feedback = Feedback.lines(problems)
            transcript.concat(feedback.map { |line| "  > #{line}" })
            messages << { role: "assistant", content: reply }
            messages << { role: "user", content: feedback.join("\n") }
            next
          end

          transcript << "gave up after #{max_tries} attempts"
          return Outcome.new(Text.lines(transcript), 1)
        end
      end
    end
  end
end
