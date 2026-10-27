# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Cmd::GuardCommand do
  def run_cli(args, files: {}, stdin: "")
    reads = []
    inputs = Callmend::Inputs.new(
      lambda do |path|
        reads << path
        files.fetch(path) { raise Errno::ENOENT }
      end,
      lambda do
        reads << "<stdin>"
        stdin
      end
    )
    out = Callmend::Output.new
    code = Callmend::Cmd::Cli.run(args, inputs, out)

    [out.stdout, out.stderr, code, reads]
  end

  it "reports option syntax failures in left-to-right order without reading files" do
    cases = [
      [["repair", "--x=1", "--pretty=1"], "unknown option --x"],
      [["repair", "--pretty=1", "--x"], "option --pretty takes no value"],
      [["guard", "--schema"], "option --schema needs a value"],
      [["guard", "--schema="], "option --schema needs a non-empty value"]
    ]

    cases.each do |args, message|
      expect(run_cli(args)).to eq(["", "callmend: #{message}\n", 2, []])
    end
  end

  it "checks the required schema before tries and tries before operand count" do
    expect(run_cli(["guard", "--max-tries=0", "script.txt"])).to eq(
      ["", "callmend: guard needs --schema\n", 2, []]
    )
    expect(run_cli(["guard", "--schema=s.json", "--max-tries=0", "a", "b"])).to eq(
      ["", "callmend: invalid --max-tries value: 0\n", 2, []]
    )
  end

  it "rejects incorrect operand counts before reading any files" do
    cases = [
      [["repair"], "repair needs exactly one file"],
      [%w[repair one two], "repair needs exactly one file"],
      [["stream"], "stream needs exactly one file"],
      [["check", "schema.json"], "check needs a schema file and a file"],
      [["guard", "--schema=schema.json"], "guard needs exactly one script file"],
      [["guard", "--schema=schema.json", "one", "two"], "guard needs exactly one script file"]
    ]

    cases.each do |args, message|
      expect(run_cli(args)).to eq(["", "callmend: #{message}\n", 2, []])
    end
  end

  it "treats -- as an option terminator and accepts stdin as an operand" do
    expect(run_cli(["repair", "--", "--pretty"], files: { "--pretty" => "{}" })).to eq(
      ["{}\n", "", 0, ["--pretty"]]
    )
    expect(run_cli(["repair", "-"], stdin: "{}")).to eq(["{}\n", "", 0, ["<stdin>"]])
  end

  it "uses the last repeated settings and consumes a separate dash-prefixed value" do
    files = { "schema=final.json" => "{}", "--script" => "{}" }
    args = [
      "guard",
      "--schema",
      "-ignored.json",
      "--schema=schema=final.json",
      "--max-tries",
      "01",
      "--max-tries=01",
      "--",
      "--script"
    ]

    expect(run_cli(args, files: files)).to eq(
      ["attempt 1: ok\n{}\n", "", 0, ["schema=final.json", "--script"]]
    )
  end

  it "accepts positive one- and two-digit tries and rejects invalid boundary values" do
    valid_values = %w[1 01 99]
    valid_values.each do |value|
      expect(run_cli(
               ["guard", "--schema=s.json", "--max-tries=#{value}", "script.txt"],
               files: { "s.json" => "{}", "script.txt" => "{}" }
             )).to eq(["attempt 1: ok\n{}\n", "", 0, ["s.json", "script.txt"]])
    end

    invalid_values = [
      ["0", "callmend: invalid --max-tries value: 0\n"],
      ["00", "callmend: invalid --max-tries value: 00\n"],
      ["100", "callmend: invalid --max-tries value: 100\n"],
      ["-1", "callmend: invalid --max-tries value: -1\n"],
      ["1.0", "callmend: invalid --max-tries value: 1.0\n"],
      ["abc", "callmend: invalid --max-tries value: abc\n"],
      [" 1", "callmend: invalid --max-tries value:  1\n"]
    ]
    invalid_values.each do |value, error|
      expect(run_cli(["guard", "--schema=s.json", "--max-tries=#{value}", "script.txt"])).to eq(
        ["", error, 2, []]
      )
    end
  end

  it "loads and validates the schema before reading the script" do
    schema_error = "callmend: s.json:1:6: unexpected character \"}\"\n"
    schema_type_error = "callmend: s.json: the schema must be a JSON object\n"
    read_error = "callmend: cannot read s.json\n"
    encoding_error = "callmend: s.json: input is not valid UTF-8\n"
    script_error = "callmend: cannot read p.txt\n"
    bad_utf8 = "\xFF".b

    cases = [
      [{}, "s.json", read_error, ["s.json"]],
      [{ "s.json" => bad_utf8 }, "s.json", encoding_error, ["s.json"]],
      [{ "s.json" => "{\"a\":}" }, "s.json", schema_error, ["s.json"]],
      [{ "s.json" => "[]" }, "s.json", schema_type_error, ["s.json"]],
      [{ "s.json" => "{}" }, "p.txt", script_error, ["s.json", "p.txt"]],
      [{ "s.json" => "{}", "p.txt" => bad_utf8 },
       "p.txt",
       "callmend: p.txt: input is not valid UTF-8\n",
       ["s.json", "p.txt"]]
    ]

    cases.each do |files, script_path, error, expected_reads|
      expect(run_cli(["guard", "--schema=s.json", script_path], files: files)).to eq(
        ["", error, 2, expected_reads]
      )
    end
  end

  it "forwards the worked successful retry and a repaired success" do
    schema_text = "{\"type\":\"object\",\"required\":[\"city\",\"days\"]," \
                  "\"properties\":{\"city\":{\"type\":\"string\"}," \
                  "\"days\":{\"type\":\"integer\",\"minimum\":1}}}"
    script_text = "{\"city\": \"Paris\"}\n---\n{\"city\": \"Paris\", \"days\": 3}"

    expect(run_cli(
             ["guard", "--schema", "s.json", "p.txt"],
             files: { "s.json" => schema_text, "p.txt" => script_text }
           )).to eq(
             [
               "attempt 1: 1 problem\n  " \
               "$: missing required property \"days\"\n  " \
               "> The arguments were rejected:\n  " \
               "> - $: missing required property \"days\"\n  " \
               "> Reply with only the corrected JSON object.\n" \
               "attempt 2: ok\n" \
               "{\"city\":\"Paris\",\"days\":3}\n",
               "",
               0,
               ["s.json", "p.txt"]
             ]
           )

    expect(run_cli(
             ["guard", "--schema=s.json", "p.txt"],
             files: { "s.json" => "{}", "p.txt" => "{a:1}" }
           )).to eq(["attempt 1: ok (1 repair)\n{\"a\":1}\n", "", 0, ["s.json", "p.txt"]])
  end

  it "forwards default exhaustion and reports when the script runs out" do
    schema_text = "{\"type\":\"object\",\"required\":[\"city\",\"days\"]," \
                  "\"properties\":{\"city\":{\"type\":\"string\"}," \
                  "\"days\":{\"type\":\"integer\",\"minimum\":1}}}"
    script_text = "{\"city\": 1}\n---\n{\"city\": 2}\n---\nnope"
    expected_transcript =
      "attempt 1: 2 problems\n  " \
      "$: missing required property \"days\"\n  " \
      "$.city: expected string, got integer\n  " \
      "> The arguments were rejected:\n  " \
      "> - $: missing required property \"days\"\n  " \
      "> - $.city: expected string, got integer\n  " \
      "> Reply with only the corrected JSON object.\n" \
      "attempt 2: 2 problems\n  " \
      "$: missing required property \"days\"\n  " \
      "$.city: expected string, got integer\n  " \
      "> The arguments were rejected:\n  " \
      "> - $: missing required property \"days\"\n  " \
      "> - $.city: expected string, got integer\n  " \
      "> Reply with only the corrected JSON object.\n" \
      "attempt 3: 1 problem\n  " \
      "$: invalid JSON: 1:1: no JSON object or array found\n" \
      "gave up after 3 attempts\n"

    expect(run_cli(
             ["guard", "--schema=s.json", "p2.txt"],
             files: { "s.json" => schema_text, "p2.txt" => script_text }
           )).to eq([expected_transcript, "", 1, ["s.json", "p2.txt"]])

    exhaustion = "{\"required\":[\"a\"]}"
    exhausted = "attempt 1: 1 problem\n  " \
                "$: missing required property \"a\"\n  " \
                "> The arguments were rejected:\n  " \
                "> - $: missing required property \"a\"\n  " \
                "> Reply with only the corrected JSON object.\n" \
                "attempt 2: no reply left in the script\n"
    expect(run_cli(
             ["guard", "--schema=s.json", "p.txt"],
             files: { "s.json" => exhaustion, "p.txt" => "{}" }
           )).to eq([exhausted, "", 1, ["s.json", "p.txt"]])
  end

  it "uses the explicit retry limit and omits final-attempt feedback" do
    schema_text = "{\"type\":\"object\",\"required\":[\"city\",\"days\"]," \
                  "\"properties\":{\"city\":{\"type\":\"string\"}," \
                  "\"days\":{\"type\":\"integer\",\"minimum\":1}}}"
    script_text = "{\"city\": 1}\n---\n{\"city\": 2}\n---\nnope"
    expected_transcript =
      "attempt 1: 2 problems\n  " \
      "$: missing required property \"days\"\n  " \
      "$.city: expected string, got integer\n  " \
      "> The arguments were rejected:\n  " \
      "> - $: missing required property \"days\"\n  " \
      "> - $.city: expected string, got integer\n  " \
      "> Reply with only the corrected JSON object.\n" \
      "attempt 2: 2 problems\n  " \
      "$: missing required property \"days\"\n  " \
      "$.city: expected string, got integer\n" \
      "gave up after 2 attempts\n"

    expect(run_cli(
             ["guard", "--schema=s.json", "--max-tries=2", "p2.txt"],
             files: { "s.json" => schema_text, "p2.txt" => script_text }
           )).to eq([expected_transcript, "", 1, ["s.json", "p2.txt"]])
  end
end
