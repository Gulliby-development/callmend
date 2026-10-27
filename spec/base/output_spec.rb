# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Output do
  it "accumulates exact text in separate output streams" do
    output = described_class.new

    expect(output.stdout).to eq("")
    expect(output.stderr).to eq("")

    output.write_out("a")
    output.write_err("bad")
    output.write_out("\nβ")
    output.write_err("\n")

    expect(output.stdout).to eq("a\nβ")
    expect(output.stderr).to eq("bad\n")
  end
end
