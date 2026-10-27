# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Json::Parser do
  it "exposes the parser API and preserves the existing loader registrations" do
    result = described_class.parse("{\"n\":2,\"a\":[null,true,false,\"x\"]}")

    expect(result).to be_a(Callmend::Json::Result)
    expect(result.value).to eq(
      "n" => Callmend::Json::Num.new("2"),
      "a" => [nil, true, false, "x"]
    )
    expect(result.value.keys).to eq(%w[n a])
    expect(result.repairs).to eq([])
    expect(Callmend::Json::Repair.members).to eq(%i[line col code message])
    expect(Callmend::Json::Result.members).to eq(%i[value repairs])
    expect(Callmend::Json::ParseError < StandardError).to be(true)
    expect(Callmend::Json::ParseError.new(2, 3, "bad")).to have_attributes(
      line: 2,
      col: 3,
      message: "bad"
    )
    expect(described_class::NOT_FOUND).to eq("no JSON object or array found")
    expect(Callmend.const_defined?(:Failure)).to be(true)
    expect(Callmend.const_defined?(:Inputs)).to be(true)
    expect(Callmend.const_defined?(:Options)).to be(true)
    expect(Callmend.const_defined?(:Output)).to be(true)
    expect(Callmend.const_defined?(:Text)).to be(true)
    expect(Callmend::Json.const_defined?(:Num)).to be(true)
    expect(Callmend::Json.const_defined?(:Writer)).to be(true)
  end

  extraction_examples = [
    [
      "strict container",
      "{\"city\": \"Paris\", \"days\": 3}",
      "{\"city\":\"Paris\",\"days\":3}",
      []
    ],
    [
      "fenced container",
      "```json\n{\"city\": \"Paris\", \"days\": 3,}\n```",
      "{\"city\":\"Paris\",\"days\":3}",
      [
        [1, 1, "R01", "code fence removed"],
        [2, 28, "R07", "trailing comma removed"]
      ]
    ],
    [
      "surrounding prose",
      "Here you go: {\"a\": 1} hope it helps",
      "{\"a\":1}",
      [
        [1, 1, "R02", "text before the value skipped"],
        [1, 23, "R03", "text after the value ignored"]
      ]
    ],
    [
      "first container",
      "text [1, 2] and {\"x\": 1}",
      "[1,2]",
      [
        [1, 1, "R02", "text before the value skipped"],
        [1, 13, "R03", "text after the value ignored"]
      ]
    ],
    [
      "initial BOM",
      "\uFEFF{\"bom\": true}",
      "{\"bom\":true}",
      []
    ],
    [
      "leading whitespace",
      "  \n\n {\"late\": 1}",
      "{\"late\":1}",
      []
    ],
    [
      "unassociated closing fence",
      "{\"a\": 1}\n```\ntrailing",
      "{\"a\":1}",
      [[2, 1, "R03", "text after the value ignored"]]
    ],
    [
      "extra closing delimiter",
      "{\"a\": 1}}",
      "{\"a\":1}",
      [[1, 9, "R03", "text after the value ignored"]]
    ]
  ]

  extraction_examples.each do |name, input, expected_json, expected_repairs|
    it "extracts the #{name} example" do
      result = described_class.parse(input)

      expect(Callmend::Json::Writer.dump(result.value)).to eq(expected_json)
      expect(result.repairs.map { |repair| [repair.line, repair.col, repair.code, repair.message] })
        .to eq(expected_repairs)

      if name == "fenced container"
        fenced_prose_examples = [
          [
            "leading prose",
            "```json\nHere: {}\n```",
            "{}",
            [[1, 1, "R01", "code fence removed"], [2, 1, "R02", "text before the value skipped"]]
          ],
          [
            "leading whitespace before prose",
            "```json\n \tHere: [1]\n```",
            "[1]",
            [[1, 1, "R01", "code fence removed"], [2, 3, "R02", "text before the value skipped"]]
          ],
          ["blank content before the value", "```json\n \t{}\n```", "{}", [[1, 1, "R01", "code fence removed"]]]
        ]

        fenced_prose_examples.each do |fence_name, fence_input, fence_json, fence_repairs|
          fenced_result = described_class.parse(fence_input)

          expect(Callmend::Json::Writer.dump(fenced_result.value)).to eq(fence_json), fence_name
          expect(fenced_result.repairs.map { |repair| [repair.line, repair.col, repair.code, repair.message] })
            .to eq(fence_repairs), fence_name
        end
      end

      if name == "unassociated closing fence"
        inline_result = described_class.parse("```json\n{} ```")
        expect(Callmend::Json::Writer.dump(inline_result.value)).to eq("{}")
        expect(inline_result.repairs.map { |repair| [repair.line, repair.col, repair.code] })
          .to eq([[1, 1, "R01"], [2, 4, "R03"]])
      end
    end
  end

  not_found_examples = [
    ["no container", "no json here", 1, 1],
    ["empty input", "", 1, 1],
    ["only whitespace", "   ", 1, 4]
  ]

  not_found_examples.each do |name, input, line, col|
    it "reports the not-found position for #{name}" do
      expect { described_class.parse(input) }.to raise_error(Callmend::Json::ParseError) { |error|
        expect(error.line).to eq(line)
        expect(error.col).to eq(col)
        expect(error.message).to eq("no JSON object or array found")
      }
    end
  end

  repair_examples = [
    [
      "bare keys",
      "{unquoted: 1, _k2: 2, k_3: 3}",
      "{\"unquoted\":1,\"_k2\":2,\"k_3\":3}",
      [
        [1, 2, "R06", "unquoted key quoted"],
        [1, 15, "R06", "unquoted key quoted"],
        [1, 23, "R06", "unquoted key quoted"]
      ]
    ],
    [
      "converted literals",
      "{\"a\": True, \"b\": False, \"c\": None}",
      "{\"a\":true,\"b\":false,\"c\":null}",
      [
        [1, 7, "R12", "literal converted"],
        [1, 18, "R12", "literal converted"],
        [1, 30, "R12", "literal converted"]
      ]
    ],
    [
      "comments between tokens",
      "{\"a\": 1 // note\n, \"b\": /* inline */ 2}",
      "{\"a\":1,\"b\":2}",
      [
        [1, 9, "R04", "comment removed"],
        [2, 8, "R04", "comment removed"]
      ]
    ],
    [
      "trailing comment",
      "{\"a\": 1} // tail",
      "{\"a\":1}",
      [[1, 10, "R04", "comment removed"]]
    ],
    [
      "object trailing comma",
      "{\"a\": 1, \"b\": 2,}",
      "{\"a\":1,\"b\":2}",
      [[1, 16, "R07", "trailing comma removed"]]
    ],
    [
      "array trailing comma",
      "[1, 2, 3,]",
      "[1,2,3]",
      [[1, 9, "R07", "trailing comma removed"]]
    ],
    [
      "missing member comma",
      "{\"a\": 1 \"b\": 2}",
      "{\"a\":1,\"b\":2}",
      [[1, 9, "R08", "missing comma added"]]
    ],
    [
      "missing element commas",
      "[1 2 \"x\" [3]]",
      "[1,2,\"x\",[3]]",
      [
        [1, 4, "R08", "missing comma added"],
        [1, 6, "R08", "missing comma added"],
        [1, 10, "R08", "missing comma added"]
      ]
    ],
    [
      "adjacent objects",
      "[{\"a\": 1} {\"b\": 2}]",
      "[{\"a\":1},{\"b\":2}]",
      [[1, 11, "R08", "missing comma added"]]
    ],
    [
      "trailing comma and suffix",
      "[1, ]]",
      "[1]",
      [
        [1, 3, "R07", "trailing comma removed"],
        [1, 6, "R03", "text after the value ignored"]
      ]
    ],
    [
      "duplicate keys",
      "{\"a\":1,\"b\":2,\"a\":3}",
      "{\"a\":3,\"b\":2}",
      []
    ]
  ]

  repair_examples.each do |name, input, expected_json, expected_repairs|
    it "repairs #{name}" do
      result = described_class.parse(input)

      expect(Callmend::Json::Writer.dump(result.value)).to eq(expected_json)
      expect(result.repairs.map { |repair| [repair.line, repair.col, repair.code, repair.message] })
        .to eq(expected_repairs)
      expect(result.value.keys).to eq(%w[a b]) if name == "duplicate keys"
    end
  end

  string_examples = [
    [
      "single-quoted strings",
      "{'a': 'it\\'s', \"b\": 'say \"hi\"'}",
      "{\"a\":\"it's\",\"b\":\"say \\\"hi\\\"\"}",
      [
        [1, 2, "R05", "single-quoted string converted"],
        [1, 7, "R05", "single-quoted string converted"],
        [1, 21, "R05", "single-quoted string converted"]
      ]
    ],
    [
      "raw controls",
      "{\"a\": \"line1\nline2\ttab\"}",
      "{\"a\":\"line1\\nline2\\ttab\"}",
      [
        [1, 13, "R10", "raw control character escaped"],
        [2, 6, "R10", "raw control character escaped"]
      ]
    ],
    [
      "invalid escapes",
      "{\"a\": \"\\q \\u00e9 \\x\"}",
      "{\"a\":\"q é x\"}",
      [
        [1, 8, "R09", "invalid escape fixed"],
        [1, 18, "R09", "invalid escape fixed"]
      ]
    ],
    [
      "surrogates and malformed Unicode escapes",
      "{\"e\": \"\\ud83d\\ude00 \\ud83d \\ude00 \\u12 \\u00zz\"}",
      "{\"e\":\"😀 � � u12 u00zz\"}",
      [
        [1, 21, "R09", "invalid escape fixed"],
        [1, 28, "R09", "invalid escape fixed"],
        [1, 35, "R09", "invalid escape fixed"],
        [1, 40, "R09", "invalid escape fixed"]
      ]
    ],
    [
      "non-ASCII Unicode",
      "{\"s\": \"café ½ 😀\"}",
      "{\"s\":\"café ½ 😀\"}",
      []
    ],
    [
      "all standard JSON escapes",
      "{\"s\":\"\\\"\\\\\\/\\b\\f\\n\\r\\t\\u0041\"}",
      "{\"s\":\"\\\"\\\\/\\b\\f\\n\\r\\tA\"}",
      []
    ]
  ]

  string_examples.each do |name, input, expected_json, expected_repairs|
    it "parses #{name}" do
      result = described_class.parse(input)

      expect(Callmend::Json::Writer.dump(result.value)).to eq(expected_json)
      expect(result.repairs.map { |repair| [repair.line, repair.col, repair.code, repair.message] })
        .to eq(expected_repairs)

      if name == "invalid escapes"
        malformed_result = described_class.parse("[\"\\u\\q\"]")
        expect(Callmend::Json::Writer.dump(malformed_result.value)).to eq("[\"uq\"]")
        expect(malformed_result.repairs.map { |repair| [repair.line, repair.col, repair.code] })
          .to eq([[1, 3, "R09"], [1, 5, "R09"]])
      end
    end
  end

  number_examples = [
    [
      "normalization",
      "{\"n\": +5, \"m\": .5, \"o\": 5., \"p\": 007, \"q\": -0.50E+3, \"r\": 1E5, \"s\": 0}",
      "{\"n\":5,\"m\":0.5,\"o\":5,\"p\":7,\"q\":-0.50e3,\"r\":1e5,\"s\":0}",
      [
        [1, 7, "R11", "number normalized"],
        [1, 16, "R11", "number normalized"],
        [1, 25, "R11", "number normalized"],
        [1, 34, "R11", "number normalized"],
        [1, 44, "R11", "number normalized"],
        [1, 59, "R11", "number normalized"]
      ]
    ],
    [
      "exponent digit limit",
      "{\"a\": 1e1000}",
      nil,
      nil
    ],
    [
      "exact decimal and leading point",
      "[+.5,9007199254740993.01]",
      "[0.5,9007199254740993.01]",
      [[1, 2, "R11", "number normalized"]]
    ]
  ]

  number_examples.each do |name, input, expected_json, expected_repairs|
    it "parses #{name}" do
      if name == "exponent digit limit"
        expect { described_class.parse(input) }.to raise_error(Callmend::Json::ParseError) { |error|
          expect(error.line).to eq(1)
          expect(error.col).to eq(7)
          expect(error.message).to eq("number out of range")
        }
      else
        result = described_class.parse(input)

        expect(Callmend::Json::Writer.dump(result.value)).to eq(expected_json)
        expect(result.repairs.map { |repair| [repair.line, repair.col, repair.code, repair.message] })
          .to eq(expected_repairs)
        next unless name == "exact decimal and leading point"

        expect(result.value[0]).to eq(Callmend::Json::Num.new("0.5"))
        expect(result.value[0].to_r).to eq(Rational(1, 2))
        expect(result.value[1]).to eq(Callmend::Json::Num.new("9007199254740993.01"))
        expect(result.value[1].to_r).to eq(Rational(900_719_925_474_099_301, 100))
      end
    end
  end

  truncation_examples = [
    [
      "open string value",
      "{\"a\": \"Par",
      "{\"a\":\"Par\"}",
      [[1, 11, "R13", "truncated input completed"]]
    ],
    [
      "cut string escape",
      "{\"a\": \"x\\",
      "{\"a\":\"x\"}",
      [[1, 10, "R13", "truncated input completed"]]
    ],
    [
      "cut Unicode escape",
      "{\"a\": \"x\\u00",
      "{\"a\":\"x\"}",
      [[1, 13, "R13", "truncated input completed"]]
    ],
    [
      "key without colon",
      "{\"a\": 1, \"b\"",
      "{\"a\":1}",
      [[1, 13, "R13", "truncated input completed"]]
    ],
    [
      "key without value",
      "{\"a\": 1, \"b\":",
      "{\"a\":1}",
      [[1, 14, "R13", "truncated input completed"]]
    ],
    [
      "cut literal word",
      "{\"a\": 1, \"b\": tru",
      "{\"a\":1}",
      [[1, 18, "R13", "truncated input completed"]]
    ],
    [
      "cut exponent",
      "{\"a\": 1, \"b\": 1e",
      "{\"a\":1}",
      [[1, 17, "R13", "truncated input completed"]]
    ],
    [
      "cut number sign",
      "{\"a\": 1, \"b\": -",
      "{\"a\":1}",
      [[1, 16, "R13", "truncated input completed"]]
    ],
    [
      "open nested array",
      "{\"a\": [1, 2",
      "{\"a\":[1,2]}",
      [[1, 12, "R13", "truncated input completed"]]
    ],
    [
      "open nested containers and string",
      "{\"a\": [1, {\"b\": \"c",
      "{\"a\":[1,{\"b\":\"c\"}]}",
      [[1, 19, "R13", "truncated input completed"]]
    ],
    [
      "final array comma",
      "[1, 2,",
      "[1,2]",
      [[1, 7, "R13", "truncated input completed"]]
    ],
    [
      "final object comma",
      "{\"a\": 1,",
      "{\"a\":1}",
      [[1, 9, "R13", "truncated input completed"]]
    ],
    [
      "open comment",
      "{\"a\": 1 /* open",
      "{\"a\":1}",
      [
        [1, 9, "R04", "comment removed"],
        [1, 16, "R13", "truncated input completed"]
      ]
    ],
    [
      "final slash",
      "{\"a\": 1 /",
      "{\"a\":1}",
      [[1, 10, "R13", "truncated input completed"]]
    ],
    [
      "open bare key",
      "{ab",
      "{}",
      [[1, 4, "R13", "truncated input completed"]]
    ],
    [
      "completed quoted key at EOF",
      "{\"a\"",
      "{}",
      [[1, 5, "R13", "truncated input completed"]]
    ],
    [
      "fenced truncation",
      "\u0060\u0060\u0060json\n{\"a\": 1",
      "{\"a\":1}",
      [
        [1, 1, "R01", "code fence removed"],
        [2, 8, "R13", "truncated input completed"]
      ]
    ]
  ]

  truncation_test_names = {
    "cut number sign" => "drops incomplete positive signs and signed exponent variants at EOF",
    "cut literal word" => "drops open quoted keys and literal prefixes at EOF",
    "final array comma" => "retains complete literals and numbers before completing open containers"
  }

  truncation_examples.each do |name, input, expected_json, expected_repairs|
    description = truncation_test_names.fetch(name, "completes #{name} according to the EOF rules")
    it description do
      result = described_class.parse(input)

      expect(Callmend::Json::Writer.dump(result.value)).to eq(expected_json)
      expect(result.repairs.map { |repair| [repair.line, repair.col, repair.code, repair.message] })
        .to eq(expected_repairs)

      if name == "cut number sign"
        incomplete_numbers = [
          ["{\"a\": 1, \"b\": +", "{\"a\":1}"],
          ["{\"a\": 1, \"b\": 1e+", "{\"a\":1}"],
          ["{\"a\": 1, \"b\": 1e-", "{\"a\":1}"]
        ]

        incomplete_numbers.each do |number_input, expected_number_json|
          number_result = described_class.parse(number_input)

          expect(Callmend::Json::Writer.dump(number_result.value)).to eq(expected_number_json)
          expect(number_result.repairs.map(&:code)).to eq(["R13"])
        end
      end

      if name == "cut literal word"
        incomplete_keys = [
          ["{\"unfinished", "{}"],
          ["{\"a\": 1, \"unfinished", "{\"a\":1}"]
        ]
        literal_prefixes = %w[t tr tru f fa fal fals n nu nul T Tr Tru F Fa Fal Fals N No Non]

        incomplete_keys.each do |key_input, expected_key_json|
          key_result = described_class.parse(key_input)

          expect(Callmend::Json::Writer.dump(key_result.value)).to eq(expected_key_json)
          expect(key_result.repairs.map(&:code)).to eq(["R13"])
        end

        literal_prefixes.each do |prefix|
          prefix_result = described_class.parse("{\"a\": 1, \"b\": #{prefix}")

          expect(Callmend::Json::Writer.dump(prefix_result.value)).to eq("{\"a\":1}")
          expect(prefix_result.repairs.map(&:code)).to eq(["R13"])
        end
      end

      next unless name == "final array comma"

      complete_values = described_class.parse("[true, false, null, 1.")

      expect(complete_values.value).to eq([true, false, nil, Callmend::Json::Num.new("1")])
      expect(complete_values.repairs.map { |repair| [repair.line, repair.col, repair.code, repair.message] })
        .to eq([
                 [1, 21, "R11", "number normalized"],
                 [1, 23, "R13", "truncated input completed"]
               ])
    end
  end

  # Supplementary EOF cases are asserted in the truncation-table examples.
  diagnostic_examples = [
    ["missing colon", "{\"a\" 1}", 1, 6, "expected ':'"],
    ["unknown word", "{\"a\": nope}", 1, 7, "unexpected word \"nope\""],
    ["combined unknown word", "{\"a\": truefalse}", 1, 7, "unexpected word \"truefalse\""],
    ["comma at object key position", "{,}", 1, 2, "expected a key"],
    ["numeric object key", "{1: 2}", 1, 2, "expected a key"],
    ["comma at array value position", "[,1]", 1, 2, "unexpected character \",\""],
    ["invalid array separator", "[1:]", 1, 3, "expected ',' or ']'"],
    ["unexpected object colon", "{\"a\" :: 1}", 1, 7, "unexpected character \":\""],
    ["invalid object separator", "{\"a\":1:}", 1, 7, "expected ',' or '}'"]
  ]

  diagnostic_examples.each do |name, input, line, col, message|
    it "reports the exact diagnostic for #{name}" do
      expect { described_class.parse(input) }.to raise_error(Callmend::Json::ParseError) { |error|
        expect(error.line).to eq(line)
        expect(error.col).to eq(col)
        expect(error.message).to eq(message)
      }
    end
  end

  repair_message_examples = [
    ["R01", "```json\n{}\n```", "code fence removed"],
    ["R02", "before {}", "text before the value skipped"],
    ["R03", "{} trailing", "text after the value ignored"],
    ["R04", "{/* note */}", "comment removed"],
    ["R05", "{'a':1}", "single-quoted string converted"],
    ["R06", "{a:1}", "unquoted key quoted"],
    ["R07", "[1,]", "trailing comma removed"],
    ["R08", "[1 2]", "missing comma added"],
    ["R09", "[\"\\q\"]", "invalid escape fixed"],
    ["R10", "[\"\u0001\"]", "raw control character escaped"],
    ["R11", "[+1]", "number normalized"],
    ["R12", "[True]", "literal converted"],
    ["R13", "[1", "truncated input completed"]
  ]

  repair_message_examples.each do |code, input, message|
    it "reports the exact message for #{code} independently" do
      result = described_class.parse(input)

      expect(result.repairs.map(&:message)).to eq([message])
    end
  end
end
