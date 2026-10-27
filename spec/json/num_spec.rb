# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Json::Num do
  examples = [
    ["0", Rational(0), true, true, "[Rational(0), true, true]", []],
    ["-12", Rational(-12), true, true, "[Rational(-12), true, true]", []],
    ["2.0", Rational(2), false, true, "[Rational(2), false, true]", []],
    [
      "1e2",
      Rational(100),
      false,
      true,
      "[Rational(100), false, true]",
      [
        ["1e010", Rational(10_000_000_000), false, true],
        ["1e008", Rational(100_000_000), false, true],
        ["1e-010", Rational(1, 10_000_000_000), false, false],
        ["1E+008", Rational(100_000_000), false, true]
      ]
    ],
    ["-0.50e3", Rational(-500), false, true, "[Rational(-500), false, true]", []],
    [
      "9007199254740993.01",
      Rational(900_719_925_474_099_301, 100),
      false,
      false,
      "[Rational(900719925474099301,100), false, false]",
      []
    ]
  ]

  examples.each do |text, rational, integer_text, whole, expected, related_cases|
    it "preserves #{text.inspect} and evaluates exactly to #{expected}" do
      number = described_class.new(text)

      expect(number.text).to eq(text)
      expect(Callmend::Json::Writer.dump(number)).to eq(text)
      expect(number.to_r).to eq(rational)
      expect(number.integer_text?).to eq(integer_text)
      expect(number.whole?).to eq(whole)

      related_cases.each do |related_text, related_rational, related_integer_text, related_whole|
        related_number = described_class.new(related_text)

        expect(related_number.text).to eq(related_text)
        expect(Callmend::Json::Writer.dump(related_number)).to eq(related_text)
        expect(related_number.to_r).to eq(related_rational)
        expect(related_number.integer_text?).to eq(related_integer_text)
        expect(related_number.whole?).to eq(related_whole)
      end
    end
  end
end
