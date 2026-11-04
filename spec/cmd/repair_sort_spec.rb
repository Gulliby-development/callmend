# frozen_string_literal: true

require "callmend"

RSpec.describe "callmend repair --sort-keys" do
  def run_cli(args, files: {})
    inputs = Callmend::Inputs.new(
      ->(path) { files.fetch(path) },
      -> { "" }
    )
    output = Callmend::Output.new
    code = Callmend::Cmd::Cli.run(args, inputs, output)
    [output.stdout, output.stderr, code]
  end

  it "writes the keys of an object in order and keeps the compact layout" do
    expect(run_cli(["repair", "--sort-keys", "a.json"], files: { "a.json" => "{\"b\": 1, \"c\": 2, \"a\": 3}" })).to eq(
      ["{\"a\":3,\"b\":1,\"c\":2}\n", "", 0]
    )
  end

  it "keeps the order of the keys without the flag" do
    expect(run_cli(["repair", "a.json"], files: { "a.json" => "{\"b\": 1, \"c\": 2, \"a\": 3}" })).to eq(
      ["{\"b\":1,\"c\":2,\"a\":3}\n", "", 0]
    )
  end

  it "sorts the objects inside arrays and inside objects and keeps the order of the arrays" do
    input = "{\"z\": [{\"y\": 1, \"x\": 2}, {\"b\": {\"d\": 1, \"c\": 2}, \"a\": 3}], \"m\": [3, 1, 2]}"

    expect(run_cli(["repair", "--sort-keys", "a.json"], files: { "a.json" => input })).to eq(
      ["{\"m\":[3,1,2],\"z\":[{\"x\":2,\"y\":1},{\"a\":3,\"b\":{\"c\":2,\"d\":1}}]}\n", "", 0]
    )
  end

  it "sorts by code point: capitals, digits, underscore, lower case, then other characters" do
    input = "{\"b\": 0, \"_\": 1, \"a\": 2, \"B\": 3, \"2\": 4, \"\\u00e9\": 5, \"\\u4e2d\": 6, \"10\": 7, \"z\": 8}"

    expect(run_cli(["repair", "--sort-keys", "a.json"], files: { "a.json" => input })).to eq(
      ["{\"10\":7,\"2\":4,\"B\":3,\"_\":1,\"a\":2,\"b\":0,\"z\":8,\"\u00e9\":5,\"\u4e2d\":6}\n", "", 0]
    )
  end

  it "sorts a key before a longer key that starts with it" do
    expect(run_cli(["repair", "--sort-keys", "a.json"], files: { "a.json" => "{\"ab\": 1, \"a\": 2, \"\": 3}" })).to eq(
      ["{\"\":3,\"a\":2,\"ab\":1}\n", "", 0]
    )
  end

  it "works with --pretty" do
    input = "{\"b\": {\"y\": 1, \"x\": 2}, \"a\": []}"

    expect(run_cli(["repair", "--pretty", "--sort-keys", "a.json"], files: { "a.json" => input })).to eq(
      ["{\n  \"a\": [],\n  \"b\": {\n    \"x\": 2,\n    \"y\": 1\n  }\n}\n", "", 0]
    )
  end

  it "works with --indent and keeps its implied --pretty" do
    input = "{\"b\": 1, \"a\": 2}"

    expect(run_cli(["repair", "--sort-keys", "--indent", "4", "a.json"], files: { "a.json" => input })).to eq(
      ["{\n    \"a\": 2,\n    \"b\": 1\n}\n", "", 0]
    )
  end

  it "sorts the keys of the value that was repaired and still reports the repairs" do
    expect(run_cli(["repair", "--sort-keys", "--report", "a.json"], files: { "a.json" => "{'b': 1, a: 2,}" })).to eq(
      [
        "{\"a\":2,\"b\":1}\n",
        "a.json:1:2: R05 single-quoted string converted\n" \
        "a.json:1:10: R06 unquoted key quoted\n" \
        "a.json:1:14: R07 trailing comma removed\n",
        0
      ]
    )
  end

  it "keeps the first place of a duplicate key and the last value, then sorts" do
    expect(run_cli(["repair", "--sort-keys", "a.json"], files: { "a.json" => "{\"b\": 1, \"a\": 2, \"b\": 3}" })).to eq(
      ["{\"a\":2,\"b\":3}\n", "", 0]
    )
  end

  it "leaves numbers, strings and empty containers as they are" do
    input = "{\"n\": 1.50, \"s\": \"x\\ny\", \"e\": {}, \"l\": []}"

    expect(run_cli(["repair", "--sort-keys", "a.json"], files: { "a.json" => input })).to eq(
      ["{\"e\":{},\"l\":[],\"n\":1.50,\"s\":\"x\\ny\"}\n", "", 0]
    )
  end

  it "prints no JSON with --strict when a repair was needed" do
    input = "{\"b\": 1, \"a\": 2,}"

    expect(run_cli(["repair", "--sort-keys", "--strict", "a.json"], files: { "a.json" => input })).to eq(
      ["", "a.json:1:16: R07 trailing comma removed\n", 1]
    )
  end

  it "takes no value" do
    expect(run_cli(["repair", "--sort-keys=yes", "a.json"], files: { "a.json" => "{}" })).to eq(
      ["", "callmend: option --sort-keys takes no value\n", 2]
    )
  end

  it "is not an option of the other commands" do
    expect(run_cli(["stream", "--sort-keys", "a.txt"], files: { "a.txt" => "\"{}\"\n" })).to eq(
      ["", "callmend: unknown option --sort-keys\n", 2]
    )
  end
end
