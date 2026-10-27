# frozen_string_literal: true

module Callmend
  module Json
    Num = Struct.new(:text) do
      def to_r
        match = /\A(-?)(0|[1-9][0-9]*)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?\z/.match(text)
        raise ArgumentError, "invalid JSON number: #{text}" unless match

        sign, integer, fraction, exponent = match.captures
        numerator = Integer("#{sign}#{integer}#{fraction}", 10)
        scale = (fraction&.length || 0) - (exponent ? Integer(exponent, 10) : 0)

        if scale.positive?
          Rational(numerator, 10**scale)
        else
          Rational(numerator * (10**-scale), 1)
        end
      end

      def integer_text?
        /\A-?[0-9]+\z/.match?(text)
      end

      def whole?
        to_r.denominator == 1
      end
    end
  end
end
