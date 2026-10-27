# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Cmd::StreamCommand do
  def run_stream(contents, path = "chunks.txt", arguments = ["stream", path])
    inputs = Callmend::Inputs.new(
      ->(requested) { { path => contents }.fetch(requested) },
      -> { raise "unexpected stdin read" }
    )
    output = Callmend::Output.new
    code = Callmend::Cmd::Cli.run(arguments, inputs, output)

    [output.stdout, output.stderr, code]
  end

  it "prints the cumulative snapshots for the four worked chunks" do
    contents = "\"Sure! \"\n" \
               "\"{\\\"a\\\": tr\"\n" \
               "\"ue, \\\"b\\\": -\"\n" \
               "\"1\"\n"

    expect(run_stream(contents, "chunks2.txt", ["stream", "chunks2.txt"])).to eq(
      [
        "chunk 1: (no value)\nchunk 2: {}\n" \
        "chunk 3: {\"a\":true}\nchunk 4: {\"a\":true,\"b\":-1}\n",
        "",
        0
      ]
    )
  end

  it "trims edge spaces, tabs and CR while skipping blank lines" do
    expect(run_stream("\n \t\"{}\"\t\r\n\n")).to eq(["chunk 1: {}\n", "", 0])
  end

  it "counts chunks independently from physical lines and preserves earlier output on failure" do
    expect(run_stream("\n\"{}\"\n\nnot a string\n", "c.txt")).to eq(
      ["chunk 1: {}\n", "callmend: c.txt:4: invalid chunk (expected a JSON string)\n", 2]
    )
  end

  it "produces no snapshots for an empty file" do
    expect(run_stream("")).to eq(["", "", 0])
  end

  it "uses the literal three-backslash chunk fixture and preserves both snapshots" do
    # Each fixture is the complete physical input: strict JSON string lines and their LF terminators.
    contents = <<~'CHUNKS'
      "{\\\"a\\\":}"
      " "
    CHUNKS
    cases = [
      [
        contents,
        "chunk 1: error: 1:2: expected a key\nchunk 2: error: 1:2: expected a key\n"
      ]
    ]

    cases.each do |file_contents, expected_stdout|
      actual = run_stream(file_contents)

      expect(actual[0]).to eq(expected_stdout)
      expect(actual.drop(1)).to eq(["", 0])
    end
  end

  it "preserves literal Unicode and decodes standard escapes and paired surrogates" do
    contents = "\"{\\\"unicode\\\":\\\"café \\\\u00e9 \\\\ud83d\\\\ude00\\\", " \
               "\\\"line\\\":\\\"a\\\\nb\\\"}\"\n"

    expect(run_stream(contents)).to eq(
      ["chunk 1: {\"unicode\":\"café é 😀\",\"line\":\"a\\nb\"}\n", "", 0]
    )
  end

  it "accepts an escaped backslash before q and an empty string as chunks" do
    expect(run_stream("\"\\\\q\"\n")).to eq(["chunk 1: (no value)\n", "", 0])
    expect(run_stream("\"\"\n")).to eq(["chunk 1: (no value)\n", "", 0])
  end

  it "rejects repaired, malformed, non-string and extra chunk values" do
    # Each row is one complete physical chunk line, including its LF; do not assemble inputs by interpolation.
    invalid_chunk_files = [
      "not a string\n",
      "'{}'\n",
      "\"x\" \"y\"\n",
      "\"x\",\n",
      "\"unfinished\n",
      "\"x\" // comment\n",
      "[]\n",
      "\"\\q\"\n",
      "\"x\tz\"\n",
      "\"\\ud800\"\n",
      "{\"a\":1}\n"
    ]

    invalid_chunk_files.each do |contents|
      expect(run_stream(contents)).to eq(
        ["", "callmend: chunks.txt:1: invalid chunk (expected a JSON string)\n", 2]
      )
    end

    expect(
      run_stream("\"ok\"\nnot a string\n", "bad_chunks.txt", ["stream", "bad_chunks.txt"])
    ).to eq(
      ["chunk 1: (no value)\n", "callmend: bad_chunks.txt:2: invalid chunk (expected a JSON string)\n", 2]
    )

    expect(run_stream("\n\"unfinished\n", "c.txt")).to eq(
      ["", "callmend: c.txt:2: invalid chunk (expected a JSON string)\n", 2]
    )
  end
end
