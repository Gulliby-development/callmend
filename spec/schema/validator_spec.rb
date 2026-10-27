# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Schema::Validator do
  num = ->(text) { Callmend::Json::Num.new(text) }

  describe ".problems" do
    type_examples = [
      ["matching string", { "type" => "string" }, "x", []],
      ["string mismatch", { "type" => "string" }, { "a" => num.call("1") },
       [["$", "expected string, got object"]]],
      ["whole decimal integer", { "type" => "integer" }, num.call("2.0"), []],
      ["fractional decimal integer mismatch", { "type" => "integer" }, num.call("2.5"),
       [["$", "expected integer, got number"]]],
      ["number mismatch", { "type" => "number" }, "2",
       [["$", "expected number, got string"]]],
      ["alternative type mismatch", { "type" => %w[string null] }, true,
       [["$", "expected string or null, got boolean"]]],
      ["boolean mismatch", { "type" => "boolean" }, [num.call("1")],
       [["$", "expected boolean, got array"]]],
      ["array mismatch", { "type" => "array" }, {},
       [["$", "expected array, got object"]]],
      ["object mismatch", { "type" => "object" }, nil,
       [["$", "expected object, got null"]]]
    ]

    type_examples.each do |name, schema, value, expected|
      it "validates the #{name} example" do
        expect(described_class.problems(schema, value)).to eq(expected)
      end
    end

    it "classifies every supported JSON value kind" do
      values = [
        [nil, "null"],
        [true, "boolean"],
        [false, "boolean"],
        %w[x string],
        [[], "array"],
        [{}, "object"],
        [num.call("-2"), "integer"],
        [num.call("2.0"), "number"],
        [num.call("1e2"), "number"]
      ]

      expect(values.map { |value, _kind| described_class.kind_of(value) }).to eq(values.map(&:last))
    end

    it "accepts a whole exponent number as an integer" do
      expect(described_class.problems({ "type" => "integer" }, Callmend::Json::Num.new("1e2"))).to eq([])
    end

    it "stops after a type mismatch" do
      schema = {
        "type" => "string",
        "enum" => [],
        "const" => false,
        "minimum" => num.call("5")
      }

      expect(described_class.problems(schema, num.call("2"))).to eq(
        [["$", "expected string, got integer"]]
      )
    end

    equality_examples = [
      ["enum mismatch", { "enum" => ["a", num.call("2"), nil] }, "b",
       [["$", "value is not one of [\"a\",2,null]"]]],
      ["numeric enum equality", { "enum" => ["a", num.call("2"), nil] }, num.call("2.0"), []],
      ["recursive object numeric equality", { "enum" => [{ "x" => num.call("1") }] },
       { "x" => num.call("1.0") }, []],
      ["array const mismatch", { "const" => { "a" => [num.call("1"), num.call("2")] } },
       { "a" => [num.call("1"), num.call("3")] },
       [["$", "value is not {\"a\":[1,2]}"]]],
      ["boolean const mismatch", { "const" => true }, num.call("1"),
       [["$", "value is not true"]]]
    ]

    equality_examples.each do |name, schema, value, expected|
      it "checks #{name}" do
        expect(described_class.problems(schema, value)).to eq(expected)
      end
    end

    it "compares nested JSON values exactly and recursively" do
      reordered_object = { "y" => [true], "x" => num.call("1.0") }
      object_schema = { "const" => { "x" => num.call("1"), "y" => [true] } }
      expect(described_class.problems(object_schema, reordered_object)).to eq([])

      array_schema = { "const" => [num.call("1"), num.call("2")] }
      expect(described_class.problems(array_schema, [num.call("2"), num.call("1")])).to eq(
        [["$", "value is not [1,2]"]]
      )

      key_schema = { "const" => { "x" => num.call("1") } }
      expect(described_class.problems(key_schema, { "x" => num.call("1"), "y" => nil })).to eq(
        [["$", "value is not {\"x\":1}"]]
      )

      boolean_schema = { "const" => { "x" => [true] } }
      expect(described_class.problems(boolean_schema, { "x" => [num.call("1")] })).to eq(
        [["$", "value is not {\"x\":[true]}"]]
      )
    end

    it "uses exact decimal equality and bounds" do
      first = num.call("9007199254740993.01")
      second = num.call("9007199254740993.02")

      expect(described_class.problems({ "enum" => [first] }, second)).to eq(
        [["$", "value is not one of [9007199254740993.01]"]]
      )
      expect(described_class.problems({ "minimum" => second }, first)).to eq(
        [["$", "number is below the minimum 9007199254740993.02"]]
      )
      expect(described_class.problems({ "maximum" => first }, second)).to eq(
        [["$", "number is above the maximum 9007199254740993.01"]]
      )
    end

    constraint_examples = [
      ["short string", { "minLength" => num.call("3") }, "ab",
       [["$", "string is shorter than 3 characters"]]],
      ["long Unicode string", { "maxLength" => num.call("1") }, "café",
       [["$", "string is longer than 1 character"]]],
      ["inclusive string minimum", { "minLength" => num.call("1") }, "x", []],
      ["number below minimum", { "minimum" => num.call("5") }, num.call("4.99"),
       [["$", "number is below the minimum 5"]]],
      ["number above maximum", { "maximum" => num.call("1.5") }, num.call("3"),
       [["$", "number is above the maximum 1.5"]]],
      ["inclusive numeric bounds", { "minimum" => num.call("-1"), "maximum" => num.call("1") },
       num.call("1.0"), []]
    ]

    constraint_examples.each do |name, schema, value, expected|
      it "validates #{name}" do
        expect(described_class.problems(schema, value)).to eq(expected)
      end
    end

    object_examples = [
      ["missing required name", { "required" => %w[a b] }, { "b" => num.call("1") },
       [["$", 'missing required property "a"']]],
      ["properties in schema order",
       { "properties" => { "a" => { "type" => "string" }, "b" => { "type" => "integer" } } },
       { "b" => "x", "a" => num.call("1") },
       [["$.a", "expected string, got integer"], ["$.b", "expected integer, got string"]]],
      ["additional properties in object order",
       { "properties" => { "a" => {} }, "additionalProperties" => false },
       { "a" => num.call("1"), "z" => num.call("2"), "y" => num.call("3") },
       [["$", 'unexpected property "z"'], ["$", 'unexpected property "y"']]],
      ["additional properties without a property map", { "additionalProperties" => false },
       { "k" => num.call("1") }, [["$", 'unexpected property "k"']]]
    ]

    object_examples.each do |name, schema, value, expected|
      it "validates the #{name} example" do
        expect(described_class.problems(schema, value)).to eq(expected)
      end
    end

    array_examples = [
      ["too few items", { "minItems" => num.call("2") }, [num.call("1")],
       [["$", "array has fewer than 2 items"]]],
      ["too many items", { "maxItems" => num.call("1") }, [num.call("1"), num.call("2")],
       [["$", "array has more than 1 item"]]],
      ["inclusive item minimum", { "minItems" => num.call("1") }, [num.call("1")], []],
      ["item errors in index order", { "items" => { "type" => "integer" } },
       [num.call("1"), "a", num.call("2"), nil],
       [["$[1]", "expected integer, got string"], ["$[3]", "expected integer, got null"]]]
    ]

    array_examples.each do |name, schema, value, expected|
      it "validates the #{name} example" do
        expect(described_class.problems(schema, value)).to eq(expected)
      end
    end

    path_examples = [
      ["quoted property names",
       { "properties" => { "weird key" => { "type" => "string" }, "a.b" => { "type" => "string" } } },
       { "weird key" => num.call("1"), "a.b" => num.call("2") },
       [['$["weird key"]', "expected string, got integer"],
        ['$["a.b"]', "expected string, got integer"]]],
      ["nested array and object paths",
       { "properties" => { "l" => { "items" => { "properties" => { "n" => { "type" => "string" } } } } } },
       { "l" => [{ "n" => num.call("1") }, { "n" => "ok" }, { "n" => nil }] },
       [["$.l[0].n", "expected string, got integer"], ["$.l[2].n", "expected string, got null"]]]
    ]

    path_examples.each do |name, schema, value, expected|
      it "constructs #{name}" do
        expect(described_class.problems(schema, value)).to eq(expected)
      end
    end

    it "validates required, properties, and additional properties in order" do
      schema = {
        "additionalProperties" => false,
        "properties" => { "known" => { "type" => "string" } },
        "required" => ["missing"]
      }
      value = { "extra" => num.call("1"), "known" => num.call("2") }

      expect(described_class.problems(schema, value)).to eq(
        [["$", 'missing required property "missing"'],
         ["$.known", "expected string, got integer"],
         ["$", 'unexpected property "extra"']]
      )
    end

    it "validates array limits before elements" do
      schema = { "items" => { "type" => "integer" }, "maxItems" => num.call("1"),
                 "minItems" => num.call("3") }
      value = ["bad", num.call("2")]

      expect(described_class.problems(schema, value)).to eq(
        [["$", "array has fewer than 3 items"], ["$", "array has more than 1 item"],
         ["$[0]", "expected integer, got string"]]
      )
    end

    it "uses Unicode code points and inclusive empty and zero boundaries" do
      expect(described_class.problems({ "minLength" => num.call("1"), "maxLength" => num.call("1") }, "😀"))
        .to eq([])
      expect(described_class.problems({ "minLength" => num.call("0"), "maxLength" => num.call("0") }, ""))
        .to eq([])
      expect(described_class.problems({ "minItems" => num.call("0"), "maxItems" => num.call("0") }, []))
        .to eq([])
    end

    it "constructs escaped custom-root paths for all property-name forms" do
      schema = {
        "properties" => {
          "simple_name9" => { "type" => "string" },
          "0lead" => { "type" => "string" },
          "" => { "type" => "string" },
          "a.b" => { "type" => "string" },
          "a\"b" => { "type" => "string" },
          "line\n" => { "type" => "string" },
          "é" => { "type" => "string" }
        }
      }
      value = {
        "simple_name9" => num.call("1"),
        "0lead" => num.call("1"),
        "" => num.call("1"),
        "a.b" => num.call("1"),
        "a\"b" => num.call("1"),
        "line\n" => num.call("1"),
        "é" => num.call("1")
      }
      expected = [
        ["root.simple_name9", "expected string, got integer"],
        ['root["0lead"]', "expected string, got integer"],
        ['root[""]', "expected string, got integer"],
        ['root["a.b"]', "expected string, got integer"],
        ['root["a\"b"]', "expected string, got integer"],
        ['root["line\\n"]', "expected string, got integer"],
        ['root["é"]', "expected string, got integer"]
      ]

      expect(described_class.problems(schema, value, "root")).to eq(expected)
    end

    it "checks the combined string keywords in their specified order" do
      schema = {
        "maxLength" => num.call("1"),
        "const" => "z",
        "minLength" => num.call("3"),
        "enum" => []
      }

      expect(described_class.problems(schema, "ab")).to eq(
        [["$", "value is not one of []"], ["$", 'value is not "z"'],
         ["$", "string is shorter than 3 characters"], ["$", "string is longer than 1 character"]]
      )
    end

    it "ignores every malformed type, enum, required, and unknown keyword" do
      value = { "x" => num.call("1") }
      [{ "type" => [] }, { "type" => "bogus" }, { "type" => ["string", 1] },
       { "enum" => false }, { "required" => ["a", 1] }, { "unknown" => true },
       { "type" => ["string", 1], "enum" => false, "required" => ["a", 1],
         "properties" => { "x" => false }, "unknown" => true }].each do |schema|
        expect(described_class.problems(schema, value)).to eq([])
      end
    end

    it "ignores malformed properties, items, and child schemas" do
      value = { "known" => num.call("1"), "extra" => num.call("2") }
      schema = { "properties" => { "known" => false }, "items" => false }
      expect(described_class.problems(schema, value)).to eq([])
      expect(described_class.problems({ "properties" => false, "additionalProperties" => false }, value)).to eq(
        [["$", 'unexpected property "known"'], ["$", 'unexpected property "extra"']]
      )
      expect(described_class.problems({ "additionalProperties" => 0 }, value)).to eq([])
    end

    it "ignores invalid limits and bounds while retaining a null const" do
      invalid_limits = [num.call("-1"), num.call("1.5"), num.call("1.0"), "1"]
      invalid_limits.each do |limit|
        expect(described_class.problems({ "minLength" => limit, "maxLength" => limit }, "")).to eq([])
        expect(described_class.problems({ "minItems" => limit, "maxItems" => limit }, [])).to eq([])
      end
      expect(described_class.problems({ "minimum" => "0", "maximum" => num.call("invalid") }, num.call("1")))
        .to eq([])
      expect(described_class.problems({ "const" => nil }, true)).to eq([["$", "value is not null"]])
    end
  end
end
