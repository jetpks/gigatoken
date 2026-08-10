//! The process-global cache-budget knob, read once per tokenizer
//! construction. Mirrors the pyo3 mechanism in the core crate's
//! `src/bindings/cache.rs`, which is `pub(crate)` in a different crate and
//! so cannot be called directly from here — the encode-cache semantics
//! themselves live in `gigatoken_rs::Tokenizer::set_max_cache_bytes` and
//! `gigatoken_rs::SentencePieceBPE::set_max_cache_bytes`.

use gigatoken_rs::{SentencePieceBPE, Tokenizer};
use std::sync::Mutex;

/// The budget applied to tokenizers constructed after the last
/// `set_max_cache_bytes` call; `None` = unbounded.
static MAX_CACHE_BYTES: Mutex<Option<usize>> = Mutex::new(Some(Tokenizer::DEFAULT_MAX_CACHE_BYTES));

/// Apply the global setting to a freshly constructed tokenizer (which
/// already carries the built-in default, hence the `!=` skip).
pub(crate) fn apply_max_cache_bytes(mut tokenizer: Tokenizer) -> Tokenizer {
    let configured = *MAX_CACHE_BYTES.lock().unwrap();
    if configured != tokenizer.max_cache_bytes() {
        tokenizer.set_max_cache_bytes(configured);
    }
    tokenizer
}

/// SentencePiece analog of [`apply_max_cache_bytes`].
pub(crate) fn apply_max_cache_bytes_sp(mut model: SentencePieceBPE) -> SentencePieceBPE {
    model.set_max_cache_bytes(*MAX_CACHE_BYTES.lock().unwrap());
    model
}

pub(crate) fn set_max_cache_bytes(max_bytes: Option<usize>) {
    *MAX_CACHE_BYTES.lock().unwrap() = max_bytes;
}

pub(crate) fn get_max_cache_bytes() -> Option<usize> {
    *MAX_CACHE_BYTES.lock().unwrap()
}
