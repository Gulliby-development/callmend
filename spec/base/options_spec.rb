# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Options do
  let(:spec) { { "--pretty" => "flag", "--schema" => "value" } }

  describe ".parse" do
    [
      [[], [], {}, []],
      [["--pretty", "a.json"], ["--pretty"], {}, ["a.json"]],
      [["--pretty", "--pretty"], ["--pretty"], {}, []],
      [["--schema", "s.json"], [], { "--schema" => "s.json" }, []],
      [["--schema=s.json"], [], { "--schema" => "s.json" }, []],
      [["--schema=a=b"], [], { "--schema" => "a=b" }, []],
      [["--schema=a", "--schema", "b"], [], { "--schema" => "b" }, []],
      [["--schema", "--pretty"], [], { "--schema" => "--pretty" }, []],
      [["-", "a", "--pretty", "b"], ["--pretty"], {}, ["-", "a", "b"]],
      [["--", "--pretty", "--", "-"], [], {}, ["--pretty", "--", "-"]]
    ].each do |args, flags, settings, operands|
      it "parses #{args.inspect} into flags, settings, and ordered operands" do
        options = described_class.parse(args, spec)

        expect(options.flags).to eq(flags)
        expect(options.settings).to eq(settings)
        expect(options.operands).to eq(operands)
        if args.empty?
          expect(options.flag?("--pretty")).to eq(false)
        else
          expect(options.flag?("--pretty")).to eq(flags.include?("--pretty"))
        end
      end
    end

    [
      [["--x=1", "--pretty=1"], "unknown option --x"],
      [["--pretty=1", "--x"], "option --pretty takes no value"],
      [["--schema"], "option --schema needs a value"],
      [["--schema="], "option --schema needs a non-empty value"],
      [["--schema", ""], "option --schema needs a non-empty value"],
      [["-x"], "unknown option -x"]
    ].each do |args, message|
      it "rejects #{args.inspect} with #{message.inspect}" do
        expect { described_class.parse(args, spec) }.to raise_error(Callmend::Failure) { |failure|
          expect(failure.exit_code).to eq(2)
          expect(failure.message).to eq(message)
        }
      end
    end
  end
end
