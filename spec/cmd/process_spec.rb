# frozen_string_literal: true

require "open3"
require "rbconfig"
require "timeout"

RSpec.describe "callmend launcher" do
  it "rejects invalid UTF-8 bytes arriving on real stdin" do
    launcher = File.expand_path("../../exe/callmend", __dir__)
    stdout, stderr, status = Timeout.timeout(30) do
      Open3.capture3(
        RbConfig.ruby,
        launcher,
        "check",
        "-",
        "-",
        stdin_data: "{}\n\xFF".b,
        binmode: true
      )
    end

    expect(stdout).to eq("")
    expect(stderr).to eq("callmend: <stdin>: input is not valid UTF-8\n")
    expect(status.exitstatus).to eq(2)
  end
end
