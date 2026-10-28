# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Cmd::Cli do
  def execute_cli(args, files: {}, stdin: "", file_reader: nil)
    file_reads = []
    stdin_reads = 0
    inputs = Callmend::Inputs.new(
      lambda { |path|
        file_reads << path
        file_reader ? file_reader.call(path) : files.fetch(path)
      },
      lambda {
        stdin_reads += 1
        stdin
      }
    )
    output = Callmend::Output.new
    code = described_class.run(args, inputs, output)

    [output.stdout, output.stderr, code, file_reads, stdin_reads]
  end

  it "loads the public command APIs and exact usage" do
    expect(described_class).to respond_to(:run)
    expect(Callmend::Cmd::RepairCommand).to respond_to(:run)
    expect(Callmend::Cmd::StreamCommand).to respond_to(:run)
    expect(Callmend::Cmd::CheckCommand).to respond_to(:run, :load_schema)
    expect(Callmend::Cmd::GuardCommand).to respond_to(:run)
    expect(described_class::USAGE).to eq(
      "usage: callmend repair [--pretty] [--indent N] [--report] [--strict] FILE\n       " \
      "callmend stream FILE\n       " \
      "callmend check SCHEMA FILE\n       " \
      "callmend guard --schema SCHEMA [--max-tries N] SCRIPT\n"
    )
  end

  it "prints usage to stderr and returns 2 without a command" do
    stdout, stderr, code = execute_cli([]).first(3)

    expect(stdout).to eq("")
    expect(stderr).to eq(described_class::USAGE)
    expect(code).to eq(2)
  end

  it "prints help to stdout only when the first argument requests it" do
    [["--help"], ["-h", "ignored"]].each do |args|
      expect(execute_cli(args).first(3)).to eq([described_class::USAGE, "", 0])
    end
  end

  it "reports unknown command names as exit-two errors" do
    [
      ["unknown", "callmend: unknown command unknown\n"],
      ["19", "callmend: unknown command 19\n"]
    ].each do |command, expected_stderr|
      expect(execute_cli([command]).first(3)).to eq(["", expected_stderr, 2])
    end
  end

  it "treats command-local help as an unknown option" do
    expect(execute_cli(["repair", "--help"]).first(3)).to eq(
      ["", "callmend: unknown option --help\n", 2]
    )
  end

  it "formats the option syntax errors from the command error table" do
    [
      [["repair", "--x=1"], "callmend: unknown option --x\n"],
      [["repair", "--pretty=1"], "callmend: option --pretty takes no value\n"],
      [["guard", "--schema"], "callmend: option --schema needs a value\n"],
      [["guard", "--schema="], "callmend: option --schema needs a non-empty value\n"]
    ].each do |args, expected_stderr|
      expect(execute_cli(args).first(3)).to eq(["", expected_stderr, 2])
    end
  end

  it "formats operand-count errors and the missing-schema error" do
    [
      [["repair"], "repair needs exactly one file"],
      [["stream"], "stream needs exactly one file"],
      [["check", "s.json"], "check needs a schema file and a file"],
      [["guard", "--schema", "s.json"], "guard needs exactly one script file"],
      [["guard", "p.txt"], "guard needs --schema"]
    ].each do |args, message|
      expect(execute_cli(args).first(3)).to eq(["", "callmend: #{message}\n", 2])
    end
  end

  it "reports the leftmost option syntax error" do
    [
      [["repair", "--x", "--pretty=1"], "callmend: unknown option --x\n"],
      [["repair", "--pretty=1", "--x"], "callmend: option --pretty takes no value\n"]
    ].each do |args, expected_stderr|
      expect(execute_cli(args).first(3)).to eq(["", expected_stderr, 2])
    end
  end

  it "checks option syntax before guard-specific values" do
    result = execute_cli(["guard", "--max-tries=0", "--x"])

    expect(result.first(3)).to eq(["", "callmend: unknown option --x\n", 2])
    expect(result[3]).to eq([])
    expect(result[4]).to eq(0)
  end

  it "requires a schema before validating the guard retry count" do
    result = execute_cli(["guard", "--max-tries=0", "p.txt"])

    expect(result.first(3)).to eq(["", "callmend: guard needs --schema\n", 2])
    expect(result[3]).to eq([])
    expect(result[4]).to eq(0)
  end

  it "rejects invalid guard retry counts before reading files" do
    ["0", "00", "100", "-1", "1.0", "abc", " 1"].each do |value|
      result = execute_cli(["guard", "--schema=s.json", "--max-tries=#{value}", "p.txt"])

      expect(result.first(3)).to eq(
        ["", "callmend: invalid --max-tries value: #{value}\n", 2]
      )
      expect(result[3]).to eq([])
    end
  end

  it "does not read inputs when an operand-count check fails" do
    result = execute_cli(["check", "schema.json"])

    expect(result.first(3)).to eq(
      ["", "callmend: check needs a schema file and a file\n", 2]
    )
    expect(result[3]).to eq([])
    expect(result[4]).to eq(0)
  end

  it "honors the option terminator for a file whose name starts with a dash" do
    expect(execute_cli(["repair", "--", "--pretty"], files: { "--pretty" => "{}" }).first(3)).to eq(
      ["{}\n", "", 0]
    )
  end

  it "reads a dash operand from stdin" do
    result = execute_cli(["repair", "-"], stdin: "{}")

    expect(result.first(3)).to eq(["{}\n", "", 0])
    expect(result[3]).to eq([])
    expect(result[4]).to eq(1)
  end

  it "uses the last repeated guard values and reads schema before script" do
    files = { "old.json" => "[]", "new.json" => "{}", "p.txt" => "{}" }
    result = execute_cli(
      ["guard", "--schema=old.json", "--schema=new.json", "--max-tries=01", "p.txt"],
      files: files
    )

    expect(result.first(3)).to eq(["attempt 1: ok\n{}\n", "", 0])
    expect(result[3]).to eq(["new.json", "p.txt"])
  end

  it "converts an unreadable file into a prefixed exit-two failure" do
    result = execute_cli(
      ["repair", "missing.json"],
      file_reader: ->(_path) { raise Errno::ENOENT }
    )

    expect(result.first(3)).to eq(["", "callmend: cannot read missing.json\n", 2])
  end

  it "uses the stdin display name for invalid UTF-8 input" do
    invalid_bytes = "{}\n".b + "\xFF".b
    result = execute_cli(["repair", "-"], stdin: invalid_bytes)

    expect(result.first(3)).to eq(
      ["", "callmend: <stdin>: input is not valid UTF-8\n", 2]
    )
  end

  it "loads schemas before data and script and reports schema failures" do
    parse_failure = execute_cli(
      ["check", "s.json", "data.json"],
      files: { "s.json" => "{\"a\":}", "data.json" => "{}" }
    )
    expect(parse_failure.first(3)).to eq(
      ["", "callmend: s.json:1:6: unexpected character \"}\"\n", 2]
    )
    expect(parse_failure[3]).to eq(["s.json"])

    wrong_type = execute_cli(
      ["guard", "--schema=s.json", "p.txt"],
      files: { "s.json" => "[]", "p.txt" => "{}" }
    )
    expect(wrong_type.first(3)).to eq(
      ["", "callmend: s.json: the schema must be a JSON object\n", 2]
    )
    expect(wrong_type[3]).to eq(["s.json"])
  end

  it "preserves earlier output when a later stream chunk is invalid" do
    result = execute_cli(["stream", "chunks.txt"], files: {
                           "chunks.txt" => "\"{}\"\nnot a string\n"
                         })

    expect(result.first(3)).to eq([
                                    "chunk 1: {}\n",
                                    "callmend: chunks.txt:2: invalid chunk (expected a JSON string)\n",
                                    2
                                  ])
  end
end
