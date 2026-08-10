# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe Gigatoken::Encodings do
  describe "::NAMES" do
    it "lists exactly the packaged tiktoken encodings" do
      expect(described_class::NAMES).to eq(%w[r50k_base cl100k_base o200k_base])
    end
  end

  describe ".[]" do
    it "resolves r50k_base to its vendored rank file, scheme, and special tokens" do
      encoding = described_class["r50k_base"]
      expect(File.basename(encoding[:rank_file])).to eq("r50k_base.tiktoken")
      expect(encoding[:pretokenizer]).to eq("gpt2")
      expect(encoding[:special_tokens]).to eq({"<|endoftext|>" => 50256})
    end

    it "resolves cl100k_base to its vendored rank file, scheme, and special tokens" do
      encoding = described_class["cl100k_base"]
      expect(File.basename(encoding[:rank_file])).to eq("cl100k_base.tiktoken")
      expect(encoding[:pretokenizer]).to eq("gpt4")
      expect(encoding[:special_tokens]).to eq({
        "<|endoftext|>" => 100257,
        "<|fim_prefix|>" => 100258,
        "<|fim_middle|>" => 100259,
        "<|fim_suffix|>" => 100260,
        "<|endofprompt|>" => 100276
      })
    end

    it "resolves o200k_base to its vendored rank file, scheme, and special tokens" do
      encoding = described_class["o200k_base"]
      expect(File.basename(encoding[:rank_file])).to eq("o200k_base.tiktoken")
      expect(encoding[:pretokenizer]).to eq("o200k")
      expect(encoding[:special_tokens]).to eq({"<|endoftext|>" => 199999, "<|endofprompt|>" => 200018})
    end

    it "returns nil for an unpackaged name" do
      expect(described_class["not_an_encoding"]).to be_nil
    end

    it "points each rank file at a file that actually exists on disk" do
      described_class::NAMES.each do |name|
        expect(File.exist?(described_class[name][:rank_file])).to be(true)
      end
    end
  end

  describe ".unpackable_reason" do
    it "explains why p50k_base cannot be packaged" do
      expect(described_class.unpackable_reason("p50k_base")).to match(/dense/i)
    end

    it "returns nil for a packaged name" do
      expect(described_class.unpackable_reason("cl100k_base")).to be_nil
    end

    it "returns nil for a name with no reason on record" do
      expect(described_class.unpackable_reason("not_an_encoding")).to be_nil
    end
  end
end
