# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Cmd::RepairCommand do
  def run_cli(args, files: {}, stdin: "")
    inputs = Callmend::Inputs.new(
      ->(path) { files.fetch(path) },
      -> { stdin }
    )
    output = Callmend::Output.new
    code = Callmend::Cmd::Cli.run(args, inputs, output)
    [output.stdout, output.stderr, code]
  end

  it "reports the trailing-comma repair from the worked a.json example" do
    expect(run_cli(["repair", "--report", "a.json"], files: {
                     "a.json" => "{\"city\": \"Paris\", \"days\": 3,}"
                   })).to eq([
                               "{\"city\":\"Paris\",\"days\":3}\n",
                               "a.json:1:28: R07 trailing comma removed\n",
                               0
                             ])
  end

  it "pretty-prints the worked b.json value without diagnostics" do
    expect(run_cli(["repair", "--pretty", "b.json"], files: {
                     "b.json" => "Sure: {'city': 'Oslo', days: 2.0, ok: True} bye"
                   })).to eq([
                               "{\n  \"city\": \"Oslo\",\n  \"days\": 2.0,\n  \"ok\": true\n}\n",
                               "",
                               0
                             ])
  end

  it "returns all seven ordered diagnostics and no JSON for strict repaired input" do
    expect(run_cli(["repair", "--strict", "b.json"], files: {
                     "b.json" => "Sure: {'city': 'Oslo', days: 2.0, ok: True} bye"
                   })).to eq([
                               "",
                               "b.json:1:1: R02 text before the value skipped\n" \
                               "b.json:1:8: R05 single-quoted string converted\n" \
                               "b.json:1:16: R05 single-quoted string converted\n" \
                               "b.json:1:24: R06 unquoted key quoted\n" \
                               "b.json:1:35: R06 unquoted key quoted\n" \
                               "b.json:1:39: R12 literal converted\n" \
                               "b.json:1:45: R03 text after the value ignored\n",
                               1
                             ])
  end

  it "does not duplicate strict diagnostics when report is also requested" do
    result = run_cli(["repair", "--strict", "--report", "b.json"], files: {
                       "b.json" => "Sure: {'city': 'Oslo', days: 2.0, ok: True} bye"
                     })

    expect(result).to eq([
                           "",
                           "b.json:1:1: R02 text before the value skipped\n" \
                           "b.json:1:8: R05 single-quoted string converted\n" \
                           "b.json:1:16: R05 single-quoted string converted\n" \
                           "b.json:1:24: R06 unquoted key quoted\n" \
                           "b.json:1:35: R06 unquoted key quoted\n" \
                           "b.json:1:39: R12 literal converted\n" \
                           "b.json:1:45: R03 text after the value ignored\n",
                           1
                         ])
  end

  it "returns the repaired value from the worked cut.json example" do
    expect(run_cli(["repair", "cut.json"], files: { "cut.json" => "{\"city\": \"Pa" })).to eq([
                                                                                                "{\"city\":\"Pa\"}\n",
                                                                                                "",
                                                                                                0
                                                                                              ])
  end

  it "prints a clean value in strict mode when no repairs are needed" do
    expect(run_cli(["repair", "--strict", "-"], stdin: "{}")).to eq(["{}\n", "", 0])
  end

  it "keeps ordinary repairs silent unless report is requested" do
    expect(run_cli(["repair", "value.json"], files: { "value.json" => "{a:1,}" })).to eq([
                                                                                           "{\"a\":1}\n",
                                                                                           "",
                                                                                           0
                                                                                         ])
  end

  it "reports repairs in parser order using code-point columns" do
    expect(run_cli(["repair", "--report", "unicode.json"], files: {
                     "unicode.json" => "é: {a: True,}"
                   })).to eq([
                               "{\"a\":true}\n",
                               "unicode.json:1:1: R02 text before the value skipped\n" \
                               "unicode.json:1:5: R06 unquoted key quoted\n" \
                               "unicode.json:1:8: R12 literal converted\n" \
                               "unicode.json:1:12: R07 trailing comma removed\n",
                               0
                             ])
    expect(run_cli(["repair", "--report", "column.json"], files: {
                     "column.json" => "         {a: 1,}"
                   })).to eq([
                               "{\"a\":1}\n",
                               "column.json:1:11: R06 unquoted key quoted\n" \
                               "column.json:1:15: R07 trailing comma removed\n",
                               0
                             ])
  end

  it "reads stdin and uses its display name for parse failures" do
    expect(run_cli(["repair", "-"], stdin: "{\"ok\":true}")).to eq(["{\"ok\":true}\n", "", 0])
    expect(run_cli(["repair", "-"], stdin: "")).to eq([
                                                        "",
                                                        "callmend: <stdin>:1:1: no JSON object or array found\n",
                                                        1
                                                      ])
  end

  it "uses the file display name for a parse failure" do
    result = run_cli(["repair", "bad.json"], files: { "bad.json" => "{\"city\": }" })
    expected = ["", "callmend: bad.json:1:10: unexpected character \"}\"\n", 1]

    expect(result).to eq(expected)
  end

  it "reports an unreadable input as an exit-two failure" do
    inputs = Callmend::Inputs.new(->(_path) { raise Errno::ENOENT }, -> { "" })
    output = Callmend::Output.new

    code = Callmend::Cmd::Cli.run(["repair", "missing.json"], inputs, output)

    expect([output.stdout, output.stderr, code]).to eq(["", "callmend: cannot read missing.json\n", 2])
  end

  it "rejects a missing file operand before reading input" do
    inputs = Callmend::Inputs.new(->(_path) { raise "unexpected file read" }, -> { "" })
    output = Callmend::Output.new

    code = Callmend::Cmd::Cli.run(["repair"], inputs, output)

    expect([output.stdout, output.stderr, code]).to eq(["", "callmend: repair needs exactly one file\n", 2])
  end

  it "rejects extra file operands before reading input" do
    inputs = Callmend::Inputs.new(->(_path) { raise "unexpected file read" }, -> { "" })
    output = Callmend::Output.new

    code = Callmend::Cmd::Cli.run(["repair", "one.json", "two.json"], inputs, output)

    expect([output.stdout, output.stderr, code]).to eq(["", "callmend: repair needs exactly one file\n", 2])
  end

  [
    [["repair", "--x=1"], "callmend: unknown option --x\n"],
    [["repair", "--pretty=1"], "callmend: option --pretty takes no value\n"]
  ].each do |args, expected_stderr|
    it "rejects #{args.last} before reading input" do
      inputs = Callmend::Inputs.new(->(_path) { raise "unexpected file read" }, -> { "" })
      output = Callmend::Output.new

      code = Callmend::Cmd::Cli.run(args, inputs, output)

      expect([output.stdout, output.stderr, code]).to eq(["", expected_stderr, 2])
    end
  end
end
