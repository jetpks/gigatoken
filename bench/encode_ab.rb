#!/usr/bin/env ruby
# frozen_string_literal: true

# Reproducible evidence (I05) for the claim behind `encode_contended`'s
# `#[cold] #[inline(never)]` pair in ext/gigatoken/src/tokenizer.rs: that
# outlining the contended half of `BPETokenizer#encode` is what keeps the
# hot, uncontended path (`try_write` succeeds, three lines, never releases
# the GVL) free of an inlining-driven regression under this workspace's
# `lto = "fat"`. Under the GVL a fast-path `#encode` never yields, so two
# `#encode` calls are never inside the extension at once — the contended
# path is only reachable from a batch-holding reader, which makes it
# unreachable in a *single-threaded* benchmark. Measuring single-threaded is
# therefore the right test for an inlining artifact, not a lock-contention
# one, and this script only ever calls single `#encode`, never
# `encode_batch`/`encode_files`.
#
# `#[cold]`/`#[inline(never)]` are compile-time attributes with no
# Ruby-visible switch (and this repo's lane rules forbid inventing one in
# lib/ or the extension), so this script cannot flip them at runtime: its
# built-in "A" and "B" arms both run whatever build is currently installed
# in lib/gigatoken/gigatoken_rb.bundle. That is enough to validate the
# *methodology* (interleaving, a self-derived noise floor, distinguishing a
# real delta from noise) against itself; it is not evidence that the
# attributes matter. For that, rebuild with them stripped and rerun — see
# "Counterfactual procedure" below, and docs/rb/benchmarks.md for the
# numbers from the one time this was done.
#
#   ruby -Ilib bench/encode_ab.rb
#   GIGATOKEN_AB_ROUNDS=1 ruby -Ilib bench/encode_ab.rb   # cheap smoke run
#
# Counterfactual procedure (manual, not automated by this script):
#   1. In ext/gigatoken/src/tokenizer.rs, delete the `#[cold]` and
#      `#[inline(never)]` lines directly above `fn encode_contended`.
#   2. `bundle exec rake compile` (rebuilds lib/gigatoken/gigatoken_rb.bundle).
#   3. `ruby -Ilib bench/encode_ab.rb` — record the "A" column; that's the
#      un-outlined build's single-encode cost.
#   4. Revert step 1's edit exactly, then `bundle exec rake compile` again
#      to restore the shipped build before trusting any other measurement.

require "gigatoken"

ROUNDS = Integer(ENV.fetch("GIGATOKEN_AB_ROUNDS", 20))

SIZES = {
  "short" => [500, "The quick brown fox jumps over the lazy dog. "],
  "medium" => [40, (["lorem ipsum dolor sit amet, consectetur adipiscing elit. "] * 40).join.freeze],
  "large" => [4, (["lorem ipsum dolor sit amet, consectetur adipiscing elit. "] * 4000).join.freeze]
}.freeze

tok = Gigatoken::Tokenizer.from_encoding("cl100k_base")
tok.encode(SIZES["large"].last) # warm the pretoken cache before any timed round

# Mean seconds per #encode call over `iterations` calls against `text`.
def time_encode(tok, text, iterations)
  start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  iterations.times { tok.encode(text) }
  (Process.clock_gettime(Process::CLOCK_MONOTONIC) - start) / iterations
end

def mean(samples)
  samples.sum / samples.size.to_f
end

def format_us(seconds)
  format("%.2fus", seconds * 1_000_000)
end

def format_pct(ratio)
  format("%+.2f%%", ratio * 100)
end

samples = SIZES.each_with_object({}) { |(size, _), h| h[size] = {a_even: [], a_odd: [], b: []} }

ROUNDS.times do |round|
  # Alternate which arm runs first each round, and split arm A's own samples
  # by round parity, so the A/A control and the A/B comparison both come
  # from the same interleaved run rather than a separate all-of-A pass.
  order = round.even? ? [:a, :b] : [:b, :a]
  SIZES.each do |size, (iterations, text)|
    order.each do |arm|
      elapsed = time_encode(tok, text, iterations)
      case arm
      when :a then samples[size][round.even? ? :a_even : :a_odd] << elapsed
      when :b then samples[size][:b] << elapsed
      end
    end
  end
end

puts "GIGATOKEN_AB_ROUNDS=#{ROUNDS}"
puts

SIZES.each_key do |size|
  a_even = samples[size][:a_even]
  a_odd = samples[size][:a_odd]
  b = samples[size][:b]

  a_mean = mean(a_even + a_odd)
  b_mean = mean(b)

  puts "== #{size} =="
  puts "  A (current build):  #{format_us(a_mean)}/encode"
  puts "  B (current build):  #{format_us(b_mean)}/encode"

  if a_even.empty? || a_odd.empty?
    puts "  A/A noise floor:     insufficient rounds (need >= 2, got #{ROUNDS})"
    puts "  A/B delta:           #{format_pct((b_mean - a_mean) / a_mean)} (noise floor unavailable, cannot classify)"
  else
    floor = (mean(a_odd) - mean(a_even)).abs / a_mean
    delta = (b_mean - a_mean) / a_mean
    verdict = if delta.abs < floor
      "indistinguishable from noise"
    else
      delta.negative? ? "faster" : "slower"
    end
    puts "  A/A noise floor:     #{format_pct(floor)}"
    puts "  A/B delta:           #{format_pct(delta)} (#{verdict})"
  end
  puts
end

puts "Both arms above ran the build currently installed in lib/gigatoken " \
     "(the shipped, #[cold]-outlined encode_contended) — see this file's " \
     "header for why a true attribute-removed B arm needs a manual rebuild."
