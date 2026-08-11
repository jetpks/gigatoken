# Benchmarks: methodology and full results

The README carries the headline numbers. This is everything behind them.

## Setup

Measured 2026-07-23 on a Mac Studio M4 Max (16 cores, 128 GB RAM, macOS 26)
against an OpenWebText reconstruction (`owt_train.txt`: 11,920,511,061 bytes,
2,393,319 docs, `<|endoftext|>`-separated — within 0.015% of upstream's own
recorded corpus), GPT-2 tokenizer (`r50k_base`, confirmed empirically
equivalent to `gpt2`).

Two payload sizes, because the comparison libraries run 100–2,000x slower than
gigatoken and a full-corpus pass would take them hours per run:

- The two gigatokens are measured on the full 11.9 GB — one warm process, a
  discarded warmup, then the median of three timed runs.
- The other four libraries are measured on a 1.35 GB slice of the same corpus —
  three fresh processes each, median.

Both gigatoken builds run with the mimalloc global allocator (this gem ships
it; the Python wheel was rebuilt with it) and `MIMALLOC_PURGE_DELAY=-1` — the
workaround for a macOS 26 allocator (xzm) crash on multi-GB frees that
otherwise kills either implementation above ~1.4 GB of input.

## Results

| Subject | Corpus | MB/s (median) | Gtok/s (median) | Notes |
|---|---|---|---|---|
| **gigatoken** (this gem, Ruby) | 11.9 GB | **12,278** | **2.78** | best 12,662; GVL released during the encode, the work runs on the engine's rayon pool. Batch API: `encode_batch`/`encode_files`, plus the packed `IO::Buffer` path. On the 1.35 GB slice: 10,519. |
| **gigatoken** (Python wheel — upstream anchor) | 11.9 GB | 7,400 | 1.68 | best 7,510; same rayon core underneath. Batch API: `encode_batch`. |
| tokenizers gem (ankane) | 1.35 GB | 10.0 | 0.0023 | `encode_batch_fast`, parallel across documents. |
| tiktoken_ruby | 1.35 GB | 30.7 | 0.0070 | single-threaded — the gem has no batch API, only a per-string `encode`. |
| tokenizers (Python, Hugging Face) | 1.35 GB | 5.6 | 0.0013 | `encode_batch_fast`, parallel across documents; repeats ranged 4.9–6.4 (upstream's own M4 Max table records 6.9). |
| tiktoken (Python) | 1.35 GB | 69.7 | 0.0158 | multi-threaded batch encode across documents. |

**Ruby-vs-Ruby, concretely:** on the same 1.35 GB slice this gem runs roughly
1,050x the tokenizers gem's throughput and roughly 340x tiktoken_ruby's.

## Update 2026-07-24: the gap was a hidden memcpy, and it's fixed

The 1.66x lead in the table above wasn't the Ruby seam being fast so much as
the Python path being robbed. Under mimalloc, the `flat.shrink_to_fit()` in
the core's `Committer::finish` reallocs — i.e. copies — the gathered token
buffer: 10.8 GB at full size, roughly half a second per pass. The gem's
packed path structurally avoids that trim (`finish_external` never had one);
the Python wheel always paid it. The fix is a one-line deletion, submitted
upstream as
[marcelroed/gigatoken#38](https://github.com/marcelroed/gigatoken/issues/38)
and already applied in this fork's core.

Rerun with the fix on both sides — same box, same corpus, same warm protocol:

| Subject | Total (median) | MB/s (median) | Gtok/s (median) |
|---|---|---|---|
| **gigatoken** (this gem, Ruby, packed) | 0.958 s | **12,449** | **2.82** |
| gigatoken (Python wheel + #38 fix) | 0.975 s | 12,226 | 2.77 |

Python's full-corpus `core_encode` dropped from 1.525 s to 0.962 s (best) —
the predicted memcpy, gone — and exact token parity (2,703,638,357) held
every run. These are the two gigatoken rows the README now carries: same
engine, same speed, within 2%. The unfixed wheel numbers remain in the table
above for the record.

## Token counts match

gigatoken — Ruby or Python, same engine — counts 2,703,638,357 tokens on the
full corpus and 306,287,417 on the slice, every run. The other four libraries
all count 306,017,245 on the slice: gigatoken's count minus exactly one
`<|endoftext|>` token per document boundary (gigatoken encodes the separators;
the others receive pre-split documents). Same underlying tokenization, wildly
different throughput.

## Caveats before trusting these numbers on your own workload

- The zero-copy input path only kicks in for documents whose bytes live in a
  heap allocation rather than being embedded in the Ruby object header itself.
  Under Ruby 4.0.6's Variable Width Allocation, that embed threshold falls
  somewhere between 512 B and 1 KB (512 B still embeds; 1024 B doesn't) —
  documents under roughly a kilobyte take a copy path instead.
- Every number above comes from one big file split into documents in-process —
  a whole-file, large-document shape. A workload made of many small documents,
  each already its own Ruby object, will land differently, for the reason
  above.

None of this repeats upstream's own core-engine numbers — those are measured
independently through the Python package and live at
[marcelroed/gigatoken#benchmarks](https://github.com/marcelroed/gigatoken#benchmarks).

## 0.2.1 thread-safety benchmark (2026-08-11)

Evidence for the single-`#encode` A/B claim in the [0.2.1] CHANGELOG entry:
that outlining `encode_contended` (`#[cold] #[inline(never)]`,
`ext/gigatoken/src/tokenizer.rs`) is what keeps the uncontended `#encode`
fast path free of an inlining-driven regression under this workspace's
`lto = "fat"`. Measured 2026-08-11 on a **Mac mini/laptop-class Apple M2
Max, 12 cores, macOS 26.6.1**, Ruby 4.0.6 — a different, and less powerful,
machine than the M4 Max box the rest of this file's numbers come from, and
a shared dev machine with no attempt made to quiesce other processes beyond
closing other applications.

Method: `ruby -Ilib bench/encode_ab.rb` (`GIGATOKEN_AB_ROUNDS=20`, the
default). Single `#encode` only (never `encode_batch`/`encode_files`) on
`cl100k_base`, at three sizes — short (45 B), medium (2,280 B), large
(228,000 B) — timed as the mean of many calls per round, arms interleaved
round to round, with an A/A noise floor self-derived from the same
interleaved run (even- vs odd-round samples of arm A).

`#[cold]`/`#[inline(never)]` are compile-time attributes with no
Ruby-visible switch, so `bench/encode_ab.rb` itself can only measure
whatever build is currently installed — both its "A" and "B" arms below ran
the shipped (attributes-present) build:

| Size | A | B | A/A noise floor | A/B delta |
|---|---|---|---|---|
| short | 0.39us | 0.38us | 10.98% | -1.55% (indistinguishable) |
| medium | 3.20us | 3.14us | 5.94% | -1.91% (indistinguishable) |
| large | 288.65us | 269.24us | 11.10% | -6.73% (indistinguishable) |

**Counterfactual (attributes removed):** ran once, manually — see
`bench/encode_ab.rb`'s header comment for the exact procedure (strip
`#[cold]`/`#[inline(never)]` from `encode_contended` in
`ext/gigatoken/src/tokenizer.rs`, `bundle exec rake compile`, run the
harness, then revert and rebuild again). Combining each run's own A and B
arms (identical code within a run) into one mean per build:

| Size | Attributes present (shipped) | Attributes removed | A/A noise floor (each run) | Delta |
|---|---|---|---|---|
| short | 0.395us | 0.380us | 11.76% / 18.34% | -3.80% |
| medium | 3.215us | 3.245us | 1.02% / 0.46% | +0.93% |
| large | 282.78us | 289.64us | 10.84% / 12.37% | +2.42% |

On this machine the attributes-present-vs-removed delta at every size is
smaller than the noise floor measured in the same runs — this machine's
noise floor is wide enough (0.46%-18.34%) that it cannot resolve the
CHANGELOG's claimed effect (-9% large, -0.4% medium, +2-5% regression
un-outlined). That is a limit of this measurement, not a retraction of the
CHANGELOG's numbers, which were measured on the 16-core box named there.
Reproduce with:

```
ruby -Ilib bench/encode_ab.rb
```
