use gigatoken_rs::load_tokenizer::hf::{self, HfTokenizer};
use gigatoken_rs::pretokenize::PretokenizerType;
use magnus::{Error, Module, RString, Ruby, Value, function};

// XZM-WORKAROUND: macOS 26's xzm malloc zone SIGTRAPs on multi-GB Rust chunk
// frees (`_xzm_reclaim_mark_used_locked` assertion); routing Rust allocations
// through mimalloc avoids the xzm zone entirely.
#[global_allocator]
static GLOBAL: mimalloc::MiMalloc = mimalloc::MiMalloc;

mod cache;
mod error;
mod gvl;
mod sentencepiece;
mod sources;
mod tokenizer;

use error::raise;
use sentencepiece::SentencePieceTokenizer;
use tokenizer::BPETokenizer;

// The gigatoken core crate exposes no version constant of its own, so this
// is the ext crate's (gigatoken-rb's) version — see the builder report.
fn crate_version() -> String {
    env!("CARGO_PKG_VERSION").to_string()
}

/// The pretokenizer scheme names `BPETokenizer.from_tiktoken` and
/// `Tokenizer.load` accept — the single source of truth `Gigatoken::Tokenizer.load`
/// names in its "no scheme for a .tiktoken path" error, so that list can
/// never drift from the one `PretokenizerType::from_name` actually accepts.
fn pretokenizer_names() -> Vec<&'static str> {
    PretokenizerType::NAMES.to_vec()
}

/// The process-global encode-cache budget in bytes per worker, applied to
/// tokenizers constructed afterward; `None` removes the bound. Mirrors
/// pyo3's `set_max_cache_bytes`/`get_max_cache_bytes` (`src/bindings/cache.rs`
/// in the core crate) over the same public core API.
fn set_max_cache_bytes(max_bytes: Option<usize>) {
    cache::set_max_cache_bytes(max_bytes);
}

fn get_max_cache_bytes() -> Option<usize> {
    cache::get_max_cache_bytes()
}

/// Load a tokenizer from in-memory HuggingFace `tokenizer.json` contents.
/// Returns a `SentencePieceTokenizer` when the model uses `byte_fallback`, a
/// `BPETokenizer` otherwise — the same split as pyo3's `load_hf_json` and
/// the two classes' own `from_hf_json` constructors.
fn load_hf_json(ruby: &Ruby, data: RString) -> Result<Value, Error> {
    // SAFETY: read-only, for the duration of this synchronous call.
    let bytes = unsafe { data.as_slice() };
    match hf::load_hf_slice(bytes) {
        Ok(HfTokenizer::Bpe(tokenizer)) => Ok(ruby.into_value(BPETokenizer::from_tokenizer(tokenizer))),
        Ok(HfTokenizer::SentencePiece(tokenizer)) => Ok(ruby.into_value(SentencePieceTokenizer::from_tokenizer(tokenizer))),
        Err(e) => Err(raise(ruby, e.to_string())),
    }
}

#[magnus::init]
fn init(ruby: &Ruby) -> Result<(), Error> {
    let gigatoken = ruby.define_module("Gigatoken")?;
    let native = gigatoken.define_module("Native")?;
    native.define_module_function("crate_version", function!(crate_version, 0))?;
    native.define_module_function("load_hf_json", function!(load_hf_json, 1))?;
    native.define_module_function("pretokenizer_names", function!(pretokenizer_names, 0))?;
    native.define_module_function("set_max_cache_bytes", function!(set_max_cache_bytes, 1))?;
    native.define_module_function("get_max_cache_bytes", function!(get_max_cache_bytes, 0))?;
    sources::init(ruby, native)?;
    tokenizer::init(ruby, native)?;
    sentencepiece::init(ruby, native)?;
    Ok(())
}
