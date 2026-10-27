# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Guard::Feedback do
  feedback_cases = [
    [
      [["$", "missing required property \"days\""]],
      [
        "The arguments were rejected:",
        "- $: missing required property \"days\"",
        "Reply with only the corrected JSON object."
      ]
    ],
    [
      [
        ["$", "missing required property \"days\""],
        ["$.city", "expected string, got integer"]
      ],
      [
        "The arguments were rejected:",
        "- $: missing required property \"days\"",
        "- $.city: expected string, got integer",
        "Reply with only the corrected JSON object."
      ]
    ]
  ]

  feedback_cases.each do |problems, expected|
    it "formats #{problems.length} ordered problem(s)" do
      expect(described_class.lines(problems)).to eq(expected)
    end
  end
end
