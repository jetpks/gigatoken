# frozen_string_literal: true

require_relative "../spec_helper"

# Ruby hands one tokenizer instance to every thread, so the wrapped state has to
# be safe under concurrent use. Before the RwLock, `encode` took a mutable
# borrow of a `RefCell` that the batch paths held shared across a GVL release —
# so a batch encode racing a single encode aborted the VM with "RefCell already
# borrowed", a *fatal*, not a rescuable exception.
#
# Each example runs in a subprocess: a regression here kills the interpreter, and
# that would take the whole suite with it rather than reporting one red example.
RSpec.describe "concurrent use of a shared tokenizer" do
  def run_ruby(source)
    lib = File.expand_path("../../lib", __dir__)
    out = IO.popen([RbConfig.ruby, "-I", lib, "-e", source], err: [:child, :out], &:read)
    [$CHILD_STATUS || $?, out]
  end

  let(:preamble) { <<~RUBY }
    Warning[:experimental] = false
    require "gigatoken"
    tok = Gigatoken::Tokenizer.from_encoding("cl100k_base")
    corpus = (1..32).map { |i| "document \#{i} " + ("lorem ipsum dolor " * (i % 11 + 2)) }
  RUBY

  it "survives a batch encode racing single encodes on the same instance" do
    status, out = run_ruby(<<~RUBY)
      #{preamble}
      expected = tok.encode(corpus.first)
      big = 6.times.map { corpus.join(" ") * 40 }

      batcher = Thread.new { 40.times { tok.encode_batch(big) } }
      singles = Thread.new { 4000.times { raise "wrong" unless tok.encode(corpus.first) == expected } }
      [batcher, singles].each(&:join)
      puts "OK"
    RUBY

    expect(out).to include("OK"), "subprocess died: #{out}"
    expect(status).to be_success
  end

  it "returns identical output for the same input across many threads" do
    status, out = run_ruby(<<~RUBY)
      #{preamble}
      expected = corpus.map { |s| tok.encode(s) }

      results = 8.times.map do
        Thread.new { 200.times.flat_map { corpus.map { |s| tok.encode(s) } } }
      end.map(&:value)

      results.each do |r|
        r.each_slice(corpus.size) { |slice| raise "mismatch" unless slice == expected }
      end
      puts "OK"
    RUBY

    expect(out).to include("OK"), "subprocess died: #{out}"
    expect(status).to be_success
  end

  it "keeps decode and the vocab readers usable while a batch encode runs" do
    status, out = run_ruby(<<~RUBY)
      #{preamble}
      big = 6.times.map { corpus.join(" ") * 40 }
      expected_ids = tok.encode(corpus.first)

      batcher = Thread.new { 30.times { tok.encode_batch(big) } }
      readers = Thread.new do
        2000.times do
          raise "decode" unless tok.decode(expected_ids).is_a?(String)
          raise "vocab_size" unless tok.vocab_size.positive?
          raise "cache_entries" unless tok.cache_entries.is_a?(Integer)
        end
      end
      [batcher, readers].each(&:join)
      puts "OK"
    RUBY

    expect(out).to include("OK"), "subprocess died: #{out}"
    expect(status).to be_success
  end
end
