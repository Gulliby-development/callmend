# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Guard::Loop do
  schema = {
    "type" => "object",
    "required" => %w[city days],
    "properties" => {
      "city" => { "type" => "string" },
      "days" => { "type" => "integer", "minimum" => Callmend::Json::Num.new("1") }
    }
  }
  one_problem_feedback = "The arguments were rejected:\n- $: missing required property \"days\"\n" \
                         "Reply with only the corrected JSON object."
  two_problem_feedback = "The arguments were rejected:\n" \
                         "- $: missing required property \"days\"\n" \
                         "- $.city: expected string, got integer\n" \
                         "Reply with only the corrected JSON object."

  it "exposes the public API and returns a successful first reply" do
    expect(described_class).to respond_to(:run)
    expect(Callmend::Guard::Outcome.new("x\n", 0).to_a).to eq(["x\n", 0])
    expect(Callmend::Json::Parser).to respond_to(:parse)
    expect(Callmend::Schema::Validator).to respond_to(:problems)
    expect(Callmend::Guard::Feedback).to respond_to(:lines)
    expect(Callmend::Guard::Scripted).to respond_to(:new)

    provider = Callmend::Guard::Scripted.new("{}\n---\nnope")
    outcome = described_class.run(provider, {}, 3)

    expect(outcome.text).to eq("attempt 1: ok\n{}\n")
    expect(outcome.code).to eq(0)
    expect(provider.seen).to eq([[]])
  end

  it "reports one repair and records the empty initial conversation" do
    provider = Callmend::Guard::Scripted.new("{a:1}")
    outcome = described_class.run(provider, {}, 3)

    expect(outcome.text).to eq("attempt 1: ok (1 repair)\n{\"a\":1}\n")
    expect(outcome.code).to eq(0)
    expect(provider.seen).to eq([[]])
  end

  it "reports plural repairs and records the empty initial conversation" do
    provider = Callmend::Guard::Scripted.new("{a:True}")
    outcome = described_class.run(provider, {}, 3)

    expect(outcome.text).to eq("attempt 1: ok (2 repairs)\n{\"a\":true}\n")
    expect(outcome.code).to eq(0)
    expect(provider.seen).to eq([[]])
  end

  it "retries a rejected reply and succeeds with the corrected value" do
    first_reply = "{\"city\": \"Paris\"}"
    provider = Callmend::Guard::Scripted.new("#{first_reply}\n---\n" \
                                             "{\"city\": \"Paris\", \"days\": 3}")
    outcome = described_class.run(provider, schema, 3)

    expect(outcome.text).to eq(
      "attempt 1: 1 problem\n  " \
      "$: missing required property \"days\"\n  " \
      "> The arguments were rejected:\n  " \
      "> - $: missing required property \"days\"\n  " \
      "> Reply with only the corrected JSON object.\n" \
      "attempt 2: ok\n" \
      "{\"city\":\"Paris\",\"days\":3}\n"
    )
    expect(outcome.code).to eq(0)
    expect(provider.seen).to eq([
                                  [],
                                  [
                                    { role: "assistant", content: first_reply },
                                    { role: "user", content: one_problem_feedback }
                                  ]
                                ])
  end

  it "preserves ordered validation problems when the only attempt is rejected" do
    provider = Callmend::Guard::Scripted.new("{\"city\": 1}")
    outcome = described_class.run(provider, schema, 1)

    expect(outcome.text).to eq(
      "attempt 1: 2 problems\n  " \
      "$: missing required property \"days\"\n  " \
      "$.city: expected string, got integer\n" \
      "gave up after 1 attempts\n"
    )
    expect(outcome.code).to eq(1)
    expect(provider.seen).to eq([[]])
  end

  it "does not request a third reply after two rejected attempts use the budget" do
    first_reply = "{\"city\": 1}"
    second_reply = "{\"city\": 2}"
    provider = Callmend::Guard::Scripted.new("#{first_reply}\n---\n#{second_reply}\n---\nnope")
    outcome = described_class.run(provider, schema, 2)

    expect(outcome.text).to eq(
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
    )
    expect(outcome.code).to eq(1)
    expect(provider.seen).to eq([
                                  [],
                                  [
                                    { role: "assistant", content: first_reply },
                                    { role: "user", content: two_problem_feedback }
                                  ]
                                ])
  end

  it "accumulates retries with independent snapshots before succeeding" do
    first_reply = "{\"city\": 1}"
    second_reply = "{\"city\": 2}"
    third_reply = "{\"city\":\"Paris\",\"days\":3}"
    provider = Callmend::Guard::Scripted.new(
      "#{first_reply}\n---\n#{second_reply}\n---\n#{third_reply}"
    )
    outcome = described_class.run(provider, schema, 3)

    expect(outcome.text).to eq(
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
      "attempt 3: ok\n" \
      "{\"city\":\"Paris\",\"days\":3}\n"
    )
    expect(outcome.code).to eq(0)
    expect(provider.seen.map(&:length)).to eq([0, 2, 4])
    expect(provider.seen).to eq([
                                  [],
                                  [
                                    { role: "assistant", content: first_reply },
                                    { role: "user", content: two_problem_feedback }
                                  ],
                                  [
                                    { role: "assistant", content: first_reply },
                                    { role: "user", content: two_problem_feedback },
                                    { role: "assistant", content: second_reply },
                                    { role: "user", content: two_problem_feedback }
                                  ]
                                ])
    expect(provider.seen[0]).to eq([])
    expect(provider.seen[1][0]).not_to be(provider.seen[2][0])
    expect(provider.seen[1][1]).not_to be(provider.seen[2][1])
    expect(provider.seen[1][0][:role]).not_to be(provider.seen[2][0][:role])
    expect(provider.seen[1][0][:content]).not_to be(provider.seen[2][0][:content])
    expect(provider.seen[1][1][:role]).not_to be(provider.seen[2][1][:role])
    expect(provider.seen[1][1][:content]).not_to be(provider.seen[2][1][:content])

    provider.seen[1][0][:content].replace("changed")
    expect(provider.seen[1][0][:content]).to eq("changed")
    expect(provider.seen[2][0][:content]).to eq(first_reply)
    expect(provider.seen[2][1][:content]).to eq(two_problem_feedback)
  end

  it "turns a parse failure into feedback before accepting a later reply" do
    provider = Callmend::Guard::Scripted.new("nope\n---\n{}")
    outcome = described_class.run(provider, {}, 3)

    expect(outcome.text).to eq(
      "attempt 1: 1 problem\n  " \
      "$: invalid JSON: 1:1: no JSON object or array found\n  " \
      "> The arguments were rejected:\n  " \
      "> - $: invalid JSON: 1:1: no JSON object or array found\n  " \
      "> Reply with only the corrected JSON object.\n" \
      "attempt 2: ok\n{}\n"
    )
    expect(outcome.code).to eq(0)
    expect(provider.seen).to eq([
                                  [],
                                  [
                                    { role: "assistant", content: "nope" },
                                    {
                                      role: "user",
                                      content: "The arguments were rejected:\n" \
                                               "- $: invalid JSON: 1:1: no JSON object or array found\n" \
                                               "Reply with only the corrected JSON object."
                                    }
                                  ]
                                ])
  end

  it "preserves parse error coordinates when its only attempt is rejected" do
    provider = Callmend::Guard::Scripted.new("{\"city\": }")
    outcome = described_class.run(provider, {}, 1)

    expect(outcome.text).to eq(
      "attempt 1: 1 problem\n  " \
      "$: invalid JSON: 1:10: unexpected character \"}\"\n" \
      "gave up after 1 attempts\n"
    )
    expect(outcome.code).to eq(1)
    expect(provider.seen).to eq([[]])
  end

  it "returns immediately when the script is exhausted after a rejected reply" do
    provider = Callmend::Guard::Scripted.new("nope")
    outcome = described_class.run(provider, {}, 3)

    expect(outcome.text).to eq(
      "attempt 1: 1 problem\n  " \
      "$: invalid JSON: 1:1: no JSON object or array found\n  " \
      "> The arguments were rejected:\n  " \
      "> - $: invalid JSON: 1:1: no JSON object or array found\n  " \
      "> Reply with only the corrected JSON object.\n" \
      "attempt 2: no reply left in the script\n"
    )
    expect(outcome.code).to eq(1)
    expect(provider.seen).to eq([
                                  [],
                                  [
                                    { role: "assistant", content: "nope" },
                                    {
                                      role: "user",
                                      content: "The arguments were rejected:\n" \
                                               "- $: invalid JSON: 1:1: no JSON object or array found\n" \
                                               "Reply with only the corrected JSON object."
                                    }
                                  ]
                                ])
  end

  it "treats an empty reply as invalid JSON rather than script exhaustion" do
    provider = Callmend::Guard::Scripted.new("")
    outcome = described_class.run(provider, {}, 1)

    expect(outcome.text).to eq(
      "attempt 1: 1 problem\n  " \
      "$: invalid JSON: 1:1: no JSON object or array found\n" \
      "gave up after 1 attempts\n"
    )
    expect(outcome.code).to eq(1)
    expect(provider.seen).to eq([[]])
  end
end
