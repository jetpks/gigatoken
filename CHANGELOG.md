# Changelog

## [Unreleased]

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
