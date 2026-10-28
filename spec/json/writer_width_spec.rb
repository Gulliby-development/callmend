# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Json::Writer do
  describe ".dump with a width" do
    one = Callmend::Json::Num.new("1")

    it "indents each level by the given number of spaces" do
      expect(described_class.dump({ "a" => [one, { "b" => nil }] }, pretty: true, width: 4)).to eq(
        <<~JSON.chomp
          {
              "a": [
                  1,
                  {
                      "b": null
                  }
              ]
          }
        JSON
      )
    end

    it "uses two spaces when no width is given" do
      expect(described_class.dump([one, [one]], pretty: true)).to eq(
        <<~JSON.chomp
          [
            1,
            [
              1
            ]
          ]
        JSON
      )
    end

    it "ignores the width of compact output" do
      expect(described_class.dump({ "a" => [one, []] }, pretty: false, width: 6)).to eq("{\"a\":[1,[]]}")
    end
  end
end
