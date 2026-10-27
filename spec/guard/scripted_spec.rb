# frozen_string_literal: true

require "callmend"

RSpec.describe Callmend::Guard::Scripted do
  split_cases = [
    ["a", ["a"]],
    ["a\n", ["a"]],
    ["a\n---\nb", %w[a b]],
    ["a\n---\nb\n", %w[a b]],
    ["", [""]],
    ["\n", [""]],
    ["---", ["", ""]],
    ["café\r\n---\r\nb\r\n", %w[café b]],
    [" ---\n--- \n\t---\nx\r", [" ---\n--- \n\t---\nx\r"]],
    ["---\n---\na\n\n---\n", ["", "", "a\n", ""]]
  ]

  split_cases.each do |text, expected|
    it "splits #{text.inspect} into the expected replies" do
      expect(described_class.split(text)).to eq(expected)
    end
  end

  it "keeps per-instance reply cursors and records independent conversations after exhaustion" do
    first = described_class.new("a\n---\nb")
    second = described_class.new("a\n---\nb")

    expect(first.seen).to eq([])
    expect(second.seen).to eq([])
    expect(4.times.map { first.next_reply([]) }).to eq(["a", "b", nil, nil])
    expect(first.seen).to eq([[], [], [], []])
    expect(first.seen.map(&:object_id).uniq.length).to eq(4)
    expect(second.next_reply([])).to eq("a")
    expect(second.seen).to eq([[]])
  end

  it "retains independent snapshots of caller conversations and mutable strings" do
    role = +"assistant"
    content = +"first"
    message = { role: role, content: content }
    messages = [message]
    provider = described_class.new("")

    expect(provider.next_reply(messages)).to eq("")
    role.replace("user")
    content.replace("second")
    expect(provider.next_reply(messages)).to be_nil
    role.replace("changed")
    content.replace("changed")
    message[:role] = +"replaced"
    message[:content] = +"replaced"
    messages.clear

    expect(provider.seen).to eq([
                                  [{ role: "assistant", content: "first" }],
                                  [{ role: "user", content: "second" }]
                                ])
    expect(provider.seen).not_to be(messages)
    expect(provider.seen[0]).not_to be(messages)
    expect(provider.seen[1]).not_to be(messages)
    expect(provider.seen[0][0]).not_to be(message)
    expect(provider.seen[1][0]).not_to be(message)
    expect(provider.seen[0][0]).not_to be(provider.seen[1][0])
    expect(provider.seen[0][0][:role]).not_to be(role)
    expect(provider.seen[0][0][:content]).not_to be(content)
    expect(provider.seen[1][0][:role]).not_to be(role)
    expect(provider.seen[1][0][:content]).not_to be(content)
    expect(provider.seen[0][0][:role]).not_to be(provider.seen[1][0][:role])
    expect(provider.seen[0][0][:content]).not_to be(provider.seen[1][0][:content])
  end
end
