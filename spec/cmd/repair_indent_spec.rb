# frozen_string_literal: true

require "callmend"

RSpec.describe "callmend repair --indent" do
  def run_cli(args, files: {})
    inputs = Callmend::Inputs.new(
      ->(path) { files.fetch(path) },
      -> { "" }
    )
    output = Callmend::Output.new
    code = Callmend::Cmd::Cli.run(args, inputs, output)
    [output.stdout, output.stderr, code]
  end

  it "indents by four spaces and implies --pretty" do
    expect(run_cli(["repair", "--indent", "4", "a.json"], files: { "a.json" => "{\"a\": [1, {\"b\": null}]}" })).to eq(
      [
        <<~JSON,
          {
              "a": [
                  1,
                  {
                      "b": null
                  }
              ]
          }
        JSON
        "",
        0
      ]
    )
  end

  it "accepts the attached form and a width of one" do
    expect(run_cli(["repair", "--indent=1", "a.json"], files: { "a.json" => "[1, [2]]" })).to eq(
      [
        <<~JSON,
          [
           1,
           [
            2
           ]
          ]
        JSON
        "",
        0
      ]
    )
  end

  it "gives the same output as --pretty for a width of two" do
    files = { "a.json" => "{\"city\": \"Paris\", \"days\": 3,}" }
    expected = [
      <<~JSON,
        {
          "city": "Paris",
          "days": 3
        }
      JSON
      "",
      0
    ]

    expect(run_cli(["repair", "--indent", "2", "a.json"], files: files)).to eq(expected)
    expect(run_cli(["repair", "--pretty", "--indent", "2", "a.json"], files: files)).to eq(expected)
    expect(run_cli(["repair", "--pretty", "a.json"], files: files)).to eq(expected)
  end

  it "keeps empty containers on one line" do
    expect(run_cli(["repair", "--indent", "8", "a.json"], files: { "a.json" => "{\"a\": [], \"b\": {}}" })).to eq(
      [
        <<~JSON,
          {
                  "a": [],
                  "b": {}
          }
        JSON
        "",
        0
      ]
    )
  end

  it "rejects a width outside 1 to 8 before it reads the file" do
    message = "callmend: option --indent needs a whole number from 1 to 8\n"

    broken = { "bad.json" => "{\"city\": }" }

    expect(run_cli(["repair", "--indent", "0", "bad.json"], files: broken)).to eq(["", message, 2])
    expect(run_cli(["repair", "--indent", "9", "a.json"], files: { "a.json" => "[]" })).to eq(["", message, 2])
    expect(run_cli(["repair", "--indent", "2.5", "a.json"], files: { "a.json" => "[]" })).to eq(["", message, 2])
    expect(run_cli(["repair", "--indent", "x", "a.json"], files: { "a.json" => "[]" })).to eq(["", message, 2])
    expect(run_cli(["repair", "--indent", "02", "a.json"], files: { "a.json" => "[]" })).to eq(["", message, 2])
  end

  it "reports a missing or empty value with the existing messages" do
    expect(run_cli(["repair", "a.json", "--indent"], files: { "a.json" => "[]" })).to eq(
      ["", "callmend: option --indent needs a value\n", 2]
    )
    expect(run_cli(["repair", "--indent=", "a.json"], files: { "a.json" => "[]" })).to eq(
      ["", "callmend: option --indent needs a non-empty value\n", 2]
    )
  end
end
