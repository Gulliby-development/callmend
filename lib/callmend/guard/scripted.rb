# frozen_string_literal: true

module Callmend
  module Guard
    class Scripted
      attr_reader :seen

      def self.split(text)
        normalized = text.gsub("\r\n", "\n")
        lines = normalized.split("\n", -1)
        lines.pop if normalized.end_with?("\n")

        replies = [[]]
        lines.each do |line|
          if line == "---"
            replies << []
          else
            replies.last << line
          end
        end

        replies.map { |reply_lines| reply_lines.join("\n") }
      end

      def initialize(text)
        @replies = self.class.split(text)
        @reply_index = 0
        @seen = []
      end

      def next_reply(messages)
        @seen << snapshot(messages)
        return nil if @reply_index >= @replies.length

        reply = @replies[@reply_index]
        @reply_index += 1
        reply
      end

      private

      def snapshot(messages)
        messages.map do |message|
          message.each_with_object({}) do |(key, value), copy|
            copy[key] = snapshot_value(key, value)
          end
        end
      end

      def snapshot_value(key, value)
        role_or_content = [:role, :content, "role", "content"].include?(key)
        role_or_content && value.is_a?(String) ? value.dup : value
      end
    end
  end
end
