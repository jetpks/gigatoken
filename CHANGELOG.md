# Changelog

## [0.2.1] - 2026-08-10

- **Fix a fatal crash when one tokenizer is shared across threads.** Ruby hands
  a single instance to every thread, and `#encode` took a mutable borrow of a
  `RefCell` that the batch paths held shared across a GVL release — so an
  `encode_batch` (or `encode_files`) racing an `#encode` on the same tokenizer
  aborted the VM with `RefCell already borrowed (fatal)`. Reachable from safe
  Ruby with no unsafe usage, and fatal rather than rescuable, so a threaded
  server (Falcon `--threaded`, Puma, Sidekiq) lost the whole worker.

  `BPETokenizer` now holds its tokenizer in an `RwLock`. Every long hold is a
  reader — the batch paths keep it across their GVL release, as do `decode`,
  `vocab`, `merges`, `vocab_size` and `cache_entries` — so readers never
  exclude each other. The sole writer is `#encode`, which is short.

  `#encode` takes the write guard with `try_write` on the uncontended path, so
  the common case costs one atomic and never releases the GVL. Only when it
  actually has to wait on a batch does it copy its input and move the
  wait-and-encode inside `without_gvl`: blocking there while holding the GVL
  would stall every other Ruby thread in the VM, and the guard is taken and
  dropped inside the closure so it never crosses OS threads when the scheduler
  offloads it.

  `SentencePieceTokenizer`'s model needed no interior mutability at all (every
  path only reads it) and is now a plain field; its `EncodeState` — the one
  mutable piece — moves from `RefCell` to `Mutex`, which is also what makes the
  wrapped object genuinely `Sync`.

  Covered by `spec/gigatoken/concurrency_spec.rb`, which runs each scenario in a
  subprocess: the old failure killed the interpreter, so an in-process
  regression test would take the suite down with it instead of reporting.

  Benchmarked on a 16-core arm64 box, interleaved A/B over four rounds with an
  A/A control establishing a ~1% noise floor: single encodes are neutral at
  medium sizes (-0.4%) and measurably faster on large inputs (-9%), with the
  batch path inside its (wide) noise band. An earlier revision of this change
  cost 2-5% on short and medium encodes — not lock overhead, but the contended
  path enlarging `encode` enough to flip an inlining decision under
  `lto = "fat"`. It is `#[cold]`-outlined for that reason; keep it that way.

  The single-`#encode` A/B harness behind those numbers is
  `bench/encode_ab.rb` (`ruby -Ilib bench/encode_ab.rb`); its methodology,
  the counterfactual (attributes removed) run, and this repo's own measured
  numbers live in `docs/rb/benchmarks.md` under "0.2.1 thread-safety
  benchmark". `spec/gigatoken/concurrency_spec.rb` now also drives a
  SentencePiece tokenizer (`spec/fixtures/sp_tokenizer.json`) from multiple
  threads on one shared instance, alongside the existing BPE coverage.

## [0.2.0] - 2026-08-10

- Merge upstream through [fac0114](https://github.com/marcelroed/gigatoken/commit/fac0114), including the encode-cache bound (upstream issue [#36](https://github.com/marcelroed/gigatoken/issues/36)) and the `from_tiktoken` pretokenizer/special-tokens rework ([#42](https://github.com/marcelroed/gigatoken/pull/42)).
- **Breaking:** `Gigatoken::Tokenizer.from_tiktoken` no longer guesses a
  pretokenization scheme. A `.tiktoken` rank file carries mergeable ranks
  only — the split regex and special tokens live in the code that defines
  the encoding — so `pretokenizer:` is now a required keyword and
  `special_tokens:` defaults to none, instead of silently applying the r50k
  scheme and a lone `<|endoftext|>` to every file (wrong ids, no error, for
  anything but `r50k_base`):

  ```ruby
  # before
  Gigatoken::Tokenizer.from_tiktoken("cl100k_base.tiktoken")

  # after
  Gigatoken::Tokenizer.from_tiktoken("cl100k_base.tiktoken", pretokenizer: "gpt4",
    special_tokens: {"<|endoftext|>" => 100257})
  ```

  `Tokenizer.load` on a `.tiktoken` path now raises unless `pretokenizer:` is
  given, for the same reason.
- Add `Gigatoken.max_cache_bytes` (getter/setter, default 512 MiB, `nil` for
  unbounded) and `Tokenizer#cache_entries`, exposing the core's process-global
  encode-cache budget to Ruby.
- Vendor mergeable ranks for the `r50k_base`, `cl100k_base`, and `o200k_base`
  tiktoken encodings (see `lib/gigatoken/encodings/PROVENANCE.md` for exact
  hashes and source URLs) and add `Gigatoken::Tokenizer.from_encoding`, so
  they resolve by name with no network access and no writable cache
  directory. `Tokenizer.load` dispatches packaged names the same way, ahead
  of the HuggingFace-Hub-repo-id shape a bare name like `cl100k_base` would
  otherwise also match. `p50k_base` is deliberately not packaged — its ranks
  are not dense (id 50256 is left free for `<|endoftext|>`) and the rank
  loader rejects non-dense ranks — so both entry points raise
  `Gigatoken::Error` explaining that, rather than `load` falling through to
  the Hub for a name that looks like a legacy repo id.
- Add `--pretokenizer` to the `bench` and `validate` CLI commands, making the
  `.tiktoken` shape their `TOKENIZER` argument has always advertised actually
  usable: a `.tiktoken` file carries mergeable ranks only, so the split regex
  has to come from the caller, same as `Tokenizer.load` already requires.
  Without the option, a `.tiktoken` `TOKENIZER` now raises `Gigatoken::Error`
  naming the valid schemes instead of crashing; the option is accepted but
  ignored for every other `TOKENIZER` shape.
- Vendor `o200k_harmony` — no new file: it reuses `o200k_base.tiktoken`'s
  ranks and `o200k` pretokenizer scheme verbatim, differing only in its
  special-token table (10 named control tokens plus 1081 reserved slots,
  transcribed from `openai_public.py`; see
  `lib/gigatoken/encodings/PROVENANCE.md`). It's the one packaged encoding
  not checked against `tiktoken_ruby`: that gem's 0.0.17 harmony table drops
  `<|endofprompt|>` where `openai/tiktoken` 0.9.0 keeps it at id 200018, so
  the oracle is the outlier here — `spec/gigatoken/differential_spec.rb`
  proves harmony instead by reduction to `o200k_base` plus a pinned
  special-token table. `p50k_edit` now raises the same explanatory
  `Gigatoken::Error` as `p50k_base`: it loads the identical non-dense
  `p50k_base.tiktoken` ranks and is blocked for the identical reason, rather
  than falling through to the Hub for a name that looks like a legacy repo
  id.
- Add `spec/gigatoken/differential_spec.rb`, proving each packaged encoding
  byte-identical to `tiktoken_ruby` over this repo's own source and docs
  (`lib/**/*.rb`, `spec/**/*.rb`, `src/**/*.rs`, `README.md`,
  `CHANGELOG.md`): the packaged tokenizer against `encode_with_special_tokens`,
  and the same rank file loaded with `special_tokens: {}` against plain
  `encode` — two directions, because gigatoken always honours an encoding's
  special tokens and tiktoken's default `encode` does not, so a one-sided
  comparison can't tell a correct encoder from one checked against the wrong
  oracle method. `tiktoken_ruby` is a development dependency only
  (`Gemfile`), not a runtime one.

## [0.1.1] - 2026-07-24

- Remove a hidden memcpy in the core's `Committer::finish`: under mimalloc
  (this gem's global allocator), `shrink_to_fit` on the multi-GB gathered
  token buffer copies instead of trimming in place. The unpacked
  `encode_batch` path gains roughly half a second per pass at 11.9 GB; the
  packed path was never affected. One-line fix, submitted upstream as
  [marcelroed/gigatoken#38](https://github.com/marcelroed/gigatoken/issues/38).
- README and benchmark docs carry the measured post-fix numbers: 12,449 MB/s
  median on the 11.9 GB OpenWebText corpus, parity with the fixed Python
  wheel within 2%.
- Sync with upstream main.

## [0.1.0] - 2026-07-23

- Initial release: Ruby bindings for the gigatoken engine. BPE and
  SentencePiece tokenization, `tokenizer.json` / HuggingFace Hub /
  `.tiktoken` loading, native-side file tokenization (`encode_files`,
  `.gz`/`.zst` transparent), packed `IO::Buffer` results, GVL-releasing
  fiber-friendly encodes, `bench`/`validate` CLI, precompiled native gems
  for arm64-darwin / x86_64-linux / aarch64-linux.
