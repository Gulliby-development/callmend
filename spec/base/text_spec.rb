# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Text do
  plural_cases = [
    [0, "item", "0 items"],
    [1, "item", "1 item"],
    [2, "item", "2 items"]
  ]

  plural_cases.each do |count, word, expected|
    it "pluralizes #{count} #{word} count" do
      expect(described_class.plural(count, word)).to eq(expected)
      expect(described_class.plural(17, "item")).to eq("17 items") if count == 2
    end
  end

  shown_cases = [
    ["", "\"\""],
    ["abc", "\"abc\""]
  ]

  shown_cases.each do |input, expected|
    it "shows #{input.inspect}" do
      expect(described_class.shown(input)).to eq(expected)
    end
  end

  it "escapes double quotes and backslashes in shown text" do
    expect(described_class.shown("a\"b")).to eq("\"a\\\"b\"")
    expect(described_class.shown("a\\b")).to eq("\"a\\\\b\"")
  end

  control_cases = [
    ["\u0000", "\"\\x00\""],
    ["\u0001", "\"\\x01\""],
    ["\t", "\"\\x09\""],
    ["\n", "\"\\x0a\""],
    ["\r", "\"\\x0d\""],
    ["\u001f", "\"\\x1f\""],
    ["\u007f", "\"\\x7f\""]
  ]

  control_cases.each do |input, expected|
    it "escapes control character #{input.ord}" do
      expect(described_class.shown(input)).to eq(expected)
    end
  end

  it "preserves non-ASCII Unicode in shown text" do
    expect(described_class.shown("café 😀")).to eq("\"café 😀\"")
  end

  lines_cases = [
    [[], ""],
    [["a"], "a\n"],
    [%w[a b], "a\nb\n"]
  ]

  lines_cases.each do |entries, expected|
    it "joins #{entries.length} diagnostic lines" do
      expect(described_class.lines(entries)).to eq(expected)
    end
  end
end
