# frozen_string_literal: true

module Callmend
  module Guard
    module Feedback
      module_function

      def lines(problems)
        ["The arguments were rejected:", *problems.map { |path, message| "- #{path}: #{message}" },
         "Reply with only the corrected JSON object."]
      end
    end
  end
end
