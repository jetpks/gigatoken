# Vendored tiktoken encodings — provenance

The `.tiktoken` files in this directory are OpenAI's published BPE mergeable-rank
tables, vendored verbatim so `gigatoken` can resolve these encodings by name with
no network access and no writable cache directory.

Each file is a plain text table: one `base64(token_bytes) rank` pair per line. It
carries **mergeable ranks only** — the pretokenizer split regex and the special
tokens belong to the encoding's *definition*, not to the file, and live in code
(see the table below).

They live under `lib/` rather than a top-level `data/` directory because this
repo's `.gitignore` ignores `/data/` ("downloaded test data"); these are shipped
gem payload, not test fixtures.

## Files

| File | Bytes | sha256 |
|------|------:|--------|
| `r50k_base.tiktoken`   |   835,554 | `306cd27f03c1a714eca7108e03d66b7dc042abe8c258b44c199a7ed9838dd930` |
| `cl100k_base.tiktoken` | 1,681,126 | `223921b76ee99bde995b7ff738513eef100fb51d18c93597a113bcffe865b2a7` |
| `o200k_base.tiktoken`  | 3,613,922 | `446a9538cb6c348e3516120d7c08b09f57c36495e2acfffe59a5bf8b0cfb1a2d` |

## Source

Retrieved **2026-08-10** over HTTPS from OpenAI's public encodings endpoint:

```
https://openaipublic.blob.core.windows.net/encodings/r50k_base.tiktoken
https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken
https://openaipublic.blob.core.windows.net/encodings/o200k_base.tiktoken
```

These are the same URLs `openai/tiktoken` itself fetches from, in
[`tiktoken_ext/openai_public.py`](https://github.com/openai/tiktoken/blob/main/tiktoken_ext/openai_public.py).

## Authenticity

Verified three independent ways at retrieval time:

1. **Transport** — HTTPS directly from `openaipublic.blob.core.windows.net`, the
   origin OpenAI publishes and `tiktoken` itself downloads from.
2. **Publisher checksum** — each measured sha256 above matches the `expected_hash`
   OpenAI publishes for that file in `openai_public.py`, fetched separately from
   `github.com/openai/tiktoken`. Two independent channels agree on the bytes.
3. **Behavioral, against a third-party implementation** — loaded through
   `gigatoken` with the pretokenizer and special tokens below, every token id
   matched [`tiktoken_ruby`](https://github.com/IAPark/tiktoken_ruby) 0.0.17
   (which embeds its own copy of these ranks) across a corpus covering ASCII,
   CJK, ZWJ emoji sequences, combining accents, whitespace runs, source code,
   and URLs. Resulting `vocab_size`: 50257 / 100277 / 200019.

## Encoding definitions

Transcribed from `openai_public.py` (each encoding's `pat_str` and
`special_tokens`), cross-checked against upstream gigatoken's own port in
`gigatoken/_load/tiktoken.py`. The scheme names are `PretokenizerType::NAMES`
values (`src/pretokenize/options.rs`).

| Encoding | Pretokenizer scheme | Special tokens |
|---|---|---|
| `r50k_base`   | `gpt2`  | `<\|endoftext\|>`=50256 |
| `cl100k_base` | `gpt4`  | `<\|endoftext\|>`=100257, `<\|fim_prefix\|>`=100258, `<\|fim_middle\|>`=100259, `<\|fim_suffix\|>`=100260, `<\|endofprompt\|>`=100276 |
| `o200k_base`  | `o200k` | `<\|endoftext\|>`=199999, `<\|endofprompt\|>`=200018 |

`p50k_base` is deliberately absent: its ranks are not dense (50256 is left free
for `<|endoftext|>`), and the rank loader rejects non-dense ranks with
`"ranks must be dense"`. `p50k_edit` loads the same `p50k_base.tiktoken` ranks
and is absent for the identical reason.

## `o200k_harmony`

Packaged with **no new vendored file**: it reuses `o200k_base.tiktoken`'s
mergeable ranks and the `o200k` pretokenizer scheme verbatim. Confirmed
against `openai/tiktoken` 0.9.0 that `o200k_harmony()` in `openai_public.py`
calls `mergeable_ranks` with the same rank file and uses the same `pat_str` as
`o200k_base()` — only the special-token table differs.

That table (1091 entries: 10 named control tokens, 1081
`<|reserved_N|>` slots) is transcribed, not derived, from `o200k_harmony()`:
base specials `<|endoftext|>` 199999 and `<|endofprompt|>` 200018, then
`<|startoftext|>` 199998, `<|endoftext|>` 199999, `<|reserved_200000|>`
200000, `<|reserved_200001|>` 200001, `<|return|>` 200002, `<|constrain|>`
200003, `<|reserved_200004|>` 200004, `<|channel|>` 200005, `<|start|>`
200006, `<|end|>` 200007, `<|message|>` 200008, `<|reserved_200009|>` 200009,
`<|reserved_200010|>` 200010, `<|reserved_200011|>` 200011, `<|call|>`
200012, then `<|reserved_N|>` for `N` in `200013..201087`. The reserved range
is **not** contiguous from 200000 — the named control tokens sit inside
200000..200012, leaving reserved slots only at `{200000, 200001, 200004,
200009, 200010, 200011} ∪ [200013, 201087]`. A table built as "200000..201087
minus the named ids" invents `<|reserved_200002|>` and drops
`<|reserved_200018|>`; the transcription above avoids both.

**Not verified against `tiktoken_ruby`** (unlike the three encodings above):
`tiktoken_ruby` 0.0.17's own `o200k_harmony` table drops `<|endofprompt|>` —
it encodes the literal as six ordinary-text tokens rather than `[200018]` —
while treating `<|reserved_200018|>` as the sole literal at that id.
`openai/tiktoken` 0.9.0 keeps both `<|endofprompt|>` and
`<|reserved_200018|>`, at the same id, as Python dict construction preserves
both keys. `openai/tiktoken` is authoritative here; `tiktoken_ruby` is the
outlier. See `spec/gigatoken/differential_spec.rb` for the measurement and
the reduction-plus-pinning proof used in place of a `tiktoken_ruby`
comparison.

## Licence

The `tiktoken` project and its published encoding files are MIT licensed,
Copyright (c) 2022 OpenAI, Shantanu Jain. See
<https://github.com/openai/tiktoken/blob/main/LICENSE>. The files are vendored
here unmodified.
