# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Cmd::CheckCommand do
  def run_cli(args, files, stdin_text = "", reads = nil)
    inputs = Callmend::Inputs.new(
      lambda do |path|
        reads << path if reads
        files.fetch(path) { raise Errno::ENOENT }
      end,
      lambda do
        reads << "-" if reads
        stdin_text
      end
    )
    output = Callmend::Output.new
    code = Callmend::Cmd::Cli.run(args, inputs, output)
    [output.stdout, output.stderr, code]
  end

  it "loads a repaired schema publicly and silently repairs schema and data" do
    schema_text = "{type:'object',}"
    inputs = Callmend::Inputs.new(->(_path) { schema_text }, -> { raise "unexpected stdin read" })

    expect(described_class.load_schema("s.json", inputs)).to eq("type" => "object")
    expect(run_cli(
             ["check", "s.json", "data.json"],
             { "s.json" => schema_text, "data.json" => "{a:1,}" }
           )).to eq(["ok\n", "", 0])
  end

  it "prints ok for a valid value matching its schema" do
    expect(run_cli(
             ["check", "s.json", "data.json"],
             {
               "s.json" => "{\"type\":\"array\"}",
               "data.json" => "[]"
             }
           )).to eq(["ok\n", "", 0])
  end

  it "prints ordered validation problems and reads schema before stdin data" do
    reads = []

    expect(run_cli(
             ["check", "s.json", "-"],
             {
               "s.json" => "{\"type\":\"object\",\"required\":[\"city\",\"days\"]" \
                           ",\"properties\":{\"city\":{\"type\":\"string\"}," \
                           "\"days\":{\"type\":\"integer\",\"minimum\":1}}}"
             },
             "{\"city\":1,\"days\":0}",
             reads
           )).to eq(
             [
               "$.city: expected string, got integer\n$.days: number is below the minimum 1\n2 problems\n",
               "",
               1
             ]
           )
    expect(reads).to eq(["s.json", "-"])
  end

  it "uses singular problem wording for one validation problem" do
    expect(run_cli(
             ["check", "s.json", "data.json"],
             { "s.json" => "{\"required\":[\"a\"]}", "data.json" => "{}" }
           )).to eq(["$: missing required property \"a\"\n1 problem\n", "", 1])
  end

  it "prints data parse errors on stdout and returns one" do
    expect(run_cli(
             ["check", "s.json", "bad.json"],
             { "s.json" => "{}", "bad.json" => "{\"city\": }" }
           )).to eq(["error: 1:10: unexpected character \"}\"\n", "", 1])
  end

  it "reports schema parse errors before attempting to read data" do
    reads = []

    expect(run_cli(
             ["check", "s.json", "missing.json"],
             { "s.json" => "{\"a\":}" },
             "",
             reads
           )).to eq(["", "callmend: s.json:1:6: unexpected character \"}\"\n", 2])
    expect(reads).to eq(["s.json"])
  end

  it "rejects a non-object schema before attempting to read data" do
    reads = []

    expect(run_cli(["check", "s.json", "missing.json"], { "s.json" => "[]" }, "", reads)).to eq(
      ["", "callmend: s.json: the schema must be a JSON object\n", 2]
    )
    expect(reads).to eq(["s.json"])
  end

  it "reports an unreadable data file after loading the schema" do
    reads = []

    expect(run_cli(["check", "s.json", "missing.json"], { "s.json" => "{}" }, "", reads)).to eq(
      ["", "callmend: cannot read missing.json\n", 2]
    )
    expect(reads).to eq(["s.json", "missing.json"])
  end

  it "shows the stdin display name when stdin is not valid UTF-8" do
    invalid_utf8_cases = [
      ["{}\n\xFF".b, "callmend: <stdin>: input is not valid UTF-8\n", ["s.json", "-"]]
    ]

    invalid_utf8_cases.each do |invalid_utf8, expected_stderr, expected_reads|
      reads = []
      expect(run_cli(["check", "s.json", "-"], { "s.json" => "{}" }, invalid_utf8, reads)).to eq(
        ["", expected_stderr, 2]
      )
      expect(reads).to eq(expected_reads)
    end
  end

  it "treats a schema repaired from a non-JSON prefix as a valid object" do
    expect(run_cli(
             ["check", "s.json", "data.json"],
             { "s.json" => "schema: {\"type\":\"object\"}", "data.json" => "{\"a\":1}" }
           )).to eq(["ok\n", "", 0])
  end
end
