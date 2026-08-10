# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "gigatoken bench (integration)" do
  root = File.expand_path("../..", __dir__)

  it "runs against the GPT-2 fixture tokenizer and a fixture corpus" do
    output = IO.popen(
      %w[ruby -Ilib exe/gigatoken bench tests/fixtures/gpt2_tokenizer.json spec/fixtures/docs.txt --doc-separator <|endoftext|>],
      chdir: root, err: [:child, :out], &:read
    )
    status = $?

    expect(status).to be_success
    expect(output).to match(/\A\s*cpu: .+\n/)
    expect(output).to match(/gigatoken: +[\d.]+ s \| +[\d.]+ MB at +[\d.]+ MB\/s \| +[\d.]+ Mtok at +[\d.]+ Mtok\/s\n\z/)
  end

  it "runs against a .tiktoken fixture when given --pretokenizer" do
    output = IO.popen(
      %w[ruby -Ilib exe/gigatoken bench spec/fixtures/ranks.tiktoken spec/fixtures/docs.txt --pretokenizer gpt2],
      chdir: root, err: [:child, :out], &:read
    )
    status = $?

    expect(status).to be_success
    expect(output).to match(/gigatoken: +[\d.]+ s \| +[\d.]+ MB at +[\d.]+ MB\/s \| +[\d.]+ Mtok at +[\d.]+ Mtok\/s\n\z/)
  end

  it "fails cleanly against a .tiktoken fixture without --pretokenizer" do
    output = IO.popen(
      %w[ruby -Ilib exe/gigatoken bench spec/fixtures/ranks.tiktoken spec/fixtures/docs.txt],
      chdir: root, err: [:child, :out], &:read
    )
    status = $?

    expect(status).not_to be_success
    expect(output).to match(/error:.*pretokenizer/i)
    expect(output).not_to match(/\.rb:\d+:in /)
  end
end

RSpec.describe "gigatoken validate (integration)" do
  root = File.expand_path("../..", __dir__)

  it "runs against a .tiktoken fixture when given --pretokenizer" do
    output = IO.popen(
      %w[ruby -Ilib exe/gigatoken validate spec/fixtures/ranks.tiktoken spec/fixtures/docs.txt --pretokenizer gpt2],
      chdir: root, err: [:child, :out], &:read
    )
    status = $?

    expect(status).to be_success
    expect(output).to match(/validation OK: \d+ documents match/)
  end

  it "fails cleanly against a .tiktoken fixture without --pretokenizer" do
    output = IO.popen(
      %w[ruby -Ilib exe/gigatoken validate spec/fixtures/ranks.tiktoken spec/fixtures/docs.txt],
      chdir: root, err: [:child, :out], &:read
    )
    status = $?

    expect(status).not_to be_success
    expect(output).to match(/error:.*pretokenizer/i)
    expect(output).not_to match(/\.rb:\d+:in /)
  end
end
