# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Inputs do
  describe "#text" do
    [
      ["a.json", "café 😀\n"],
      ["empty", ""]
    ].each do |path, expected|
      it "reads #{path} through the file callable" do
        file_calls = []
        inputs = described_class.new(lambda { |file_path|
          file_calls << file_path
          expected
        }, lambda {
             raise "unexpected stdin read"
           })

        expect(inputs.text(path)).to eq(expected)
        expect(file_calls).to eq([path])
        expect(inputs.text(path).encoding).to eq(Encoding::UTF_8)
      end
    end

    [
      ["-", "{}\n"]
    ].each do |path, expected|
      it "reads #{path} through the stdin callable" do
        stdin_calls = 0
        inputs = described_class.new(->(_file_path) { raise "unexpected file read" }, lambda {
          stdin_calls += 1
          expected
        })

        expect(inputs.text(path)).to eq(expected)
        expect(stdin_calls).to eq(1)
        expect(inputs.text(path).encoding).to eq(Encoding::UTF_8)
      end
    end

    [
      ["missing.json", Errno::ENOENT, "cannot read missing.json"],
      ["denied", Errno::EACCES, "cannot read denied"]
    ].each do |path, error_class, message|
      it "converts #{error_class} from reading #{path} into a failure" do
        inputs = described_class.new(->(_file_path) { raise error_class }, -> { raise "unexpected stdin read" })

        expect { inputs.text(path) }.to raise_error(Callmend::Failure) do |error|
          expect(error).to be_a(StandardError)
          expect(error.exit_code).to eq(2)
          expect(error.message).to eq(message)
        end
      end
    end

    [
      ["bad.json", [255].pack("C*"), "bad.json: input is not valid UTF-8"],
      ["-", [123, 125, 10, 255].pack("C*"), "<stdin>: input is not valid UTF-8"]
    ].each do |path, bytes, message|
      it "rejects invalid UTF-8 from #{path}" do
        inputs = described_class.new(->(_file_path) { bytes }, -> { bytes })

        expect { inputs.text(path) }.to raise_error(Callmend::Failure) do |error|
          expect(error.exit_code).to eq(2)
          expect(error.message).to eq(message)
        end
      end
    end
  end

  describe ".display_name" do
    [
      ["-", "<stdin>"],
      ["a.json", "a.json"]
    ].each do |path, expected|
      it "displays #{path} as #{expected}" do
        expect(described_class.display_name(path)).to eq(expected)
      end
    end
  end
end
