# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Json::Writer do
  describe ".dump" do
    one = Callmend::Json::Num.new("1")
    two = Callmend::Json::Num.new("2")
    dump_examples = [
      ["compact object",
       { "a" => one, "b" => [one, two], "c" => {} }, false, "{\"a\":1,\"b\":[1,2],\"c\":{}}"],
      [
        "pretty object",
        { "a" => one, "b" => [one, two], "c" => {} },
        true,
        "{\n  \"a\": 1,\n  \"b\": [\n    1,\n    2\n  ],\n  \"c\": {}\n}"
      ],
      ["pretty empty array", [], true, "[]"],
      ["pretty empty object", {}, true, "{}"],
      ["pretty nested array", [[], {}, [one]], true, "[\n  [],\n  {},\n  [\n    1\n  ]\n]"],
      [
        "pretty nested object",
        { "k" => { "x" => [{ "y" => nil }] } },
        true,
        "{\n  \"k\": {\n    \"x\": [\n      {\n        \"y\": null\n      }\n    ]\n  }\n}"
      ]
    ]

    dump_examples.each do |name, value, pretty, expected|
      it "writes the #{name} example" do
        expect(described_class.dump(value, pretty: pretty)).to eq(expected)
      end
    end

    compact_values = [
      ["nil", nil, "null"],
      ["true", true, "true"],
      ["false", false, "false"]
    ]

    compact_values.each do |name, value, expected|
      it "dumps #{name} compactly" do
        expect(described_class.dump(value)).to eq(expected)
      end
    end

    it "dumps exact numeric text without changing it" do
      value = Callmend::Json::Num.new("-0.50e3")
      expect(described_class.dump(value)).to eq("-0.50e3")
      expect(described_class.dump(Callmend::Json::Num.new("16"))).to eq("16")
    end
  end

  describe ".quote" do
    it "quotes plain text and dispatches strings through dump" do
      expect(described_class.quote("abc")).to eq("\"abc\"")
      expect(described_class.dump("abc")).to eq("\"abc\"")
    end

    quote_examples = [
      ["empty text", "", "\"\""],
      ["a double quote", "a\"b", "\"a\\\"b\""],
      ["a backslash", "a\\b", "\"a\\\\b\""],
      ["a newline", "a\nb", "\"a\\nb\""],
      ["U+0001", "\u0001", "\"\\u0001\""],
      ["U+007F", "\u007f", "\"\u007f\""]
    ]

    quote_examples.each do |name, value, expected|
      it "quotes #{name}" do
        expect(described_class.quote(value)).to eq(expected)
      end
    end

    it "escapes JSON controls while preserving slash and Unicode" do
      text = "\b\f\n\r\t\u001f/ café 😀"
      expect(described_class.quote(text)).to eq("\"\\b\\f\\n\\r\\t\\u001f/ café 😀\"")
      expect(described_class.quote("18")).to eq("\"18\"")
    end
  end
end
