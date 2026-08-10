# frozen_string_literal: true

require_relative "../spec_helper"
require "tiktoken_ruby"

# Proves each packaged encoding byte-identical to tiktoken_ruby over this
# repo's own source and docs — in both directions, because gigatoken always
# honours an encoding's special tokens and tiktoken's default `encode` does
# not (this repo's own files contain "<|endoftext|>" as literal text), so a
# one-sided comparison can't tell a correct encoder from one checked against
# the wrong oracle method.
RSpec.describe "packaged encodings against tiktoken_ruby" do
  corpus_paths = (Dir["lib/**/*.rb"] + Dir["spec/**/*.rb"] + Dir["src/**/*.rs"] + ["README.md", "CHANGELOG.md"])
    .select { |path| File.file?(path) }.sort
  corpus = corpus_paths.map { |path| File.read(path, encoding: "UTF-8") }

  it "covers a non-trivial corpus of the repo's own text" do
    expect(corpus_paths.size).to be >= 60
    expect(corpus.sum(&:bytesize)).to be >= 1_000_000
  end

  Gigatoken::Encodings::NAMES.each do |name|
    describe name do
      entry = Gigatoken::Encodings[name]
      oracle = Tiktoken.get_encoding(name)

      it "is byte-identical to tiktoken_ruby's encode_with_special_tokens for the packaged tokenizer" do
        packaged = Gigatoken::Tokenizer.from_encoding(name)
        corpus.each { |text| expect(packaged.encode(text)).to eq(oracle.encode_with_special_tokens(text)) }
      end

      it "is byte-identical to tiktoken_ruby's plain encode for a special_tokens: {} tokenizer" do
        plain = Gigatoken::Tokenizer.from_tiktoken(entry[:rank_file], pretokenizer: entry[:pretokenizer], special_tokens: {})
        corpus.each { |text| expect(plain.encode(text)).to eq(oracle.encode(text)) }
      end
    end
  end
end
