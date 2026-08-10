# frozen_string_literal: true

require_relative "../spec_helper"

RSpec.describe "Gigatoken.max_cache_bytes" do
  fixture_path = File.expand_path("../../tests/fixtures/gpt2_tokenizer.json", __dir__)

  before { @original_max_cache_bytes = Gigatoken.max_cache_bytes }

  after { Gigatoken.max_cache_bytes = @original_max_cache_bytes }

  it "defaults to 512 MiB" do
    expect(Gigatoken.max_cache_bytes).to eq(512 * 1024 * 1024)
  end

  it "round-trips a set value" do
    Gigatoken.max_cache_bytes = 64 << 20
    expect(Gigatoken.max_cache_bytes).to eq(64 << 20)
  end

  it "treats nil as unbounded" do
    Gigatoken.max_cache_bytes = nil
    expect(Gigatoken.max_cache_bytes).to be_nil
  end

  it "reports an Integer cache_entries count for a freshly built tokenizer" do
    tokenizer = Gigatoken::Tokenizer.from_file(fixture_path)
    expect(tokenizer.cache_entries).to be_a(Integer)
  end

  it "applies a changed budget to tokenizers built afterward" do
    rng = Random.new(1234)
    words = Array.new(20_000) { Array.new(rng.rand(6..10)) { (rng.rand(26) + "a".ord).chr }.join }
    text = words.join(" ")

    Gigatoken.max_cache_bytes = 64 * 1024
    small = Gigatoken::Tokenizer.from_file(fixture_path)
    small_seed = small.cache_entries
    small.encode(text)
    small_growth = small.cache_entries - small_seed

    Gigatoken.max_cache_bytes = 256 * 1024 * 1024
    large = Gigatoken::Tokenizer.from_file(fixture_path)
    large_seed = large.cache_entries
    large.encode(text)
    large_growth = large.cache_entries - large_seed

    expect(small_growth).to be < large_growth / 10
  end

  it "grows cache_entries as pretokens outside the vocab seed are encoded" do
    tokenizer = Gigatoken::Tokenizer.from_file(fixture_path)
    seed = tokenizer.cache_entries

    rng = Random.new(1234)
    words = Array.new(2000) { Array.new(rng.rand(6..10)) { (rng.rand(26) + "a".ord).chr }.join }
    tokenizer.encode(words.join(" "))

    expect(tokenizer.cache_entries).to be > seed
  end
end
