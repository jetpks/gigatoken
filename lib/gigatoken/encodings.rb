# frozen_string_literal: true

module Gigatoken
  # The tiktoken encodings gigatoken vendors ranks for, and the pieces a
  # .tiktoken file doesn't carry: its pretokenizer scheme and special-token
  # table (see Tokenizer.from_tiktoken and lib/gigatoken/encodings/
  # PROVENANCE.md, the source of truth this is transcribed from).
  module Encodings
    DATA_DIR = File.expand_path("encodings", __dir__)
    private_constant :DATA_DIR

    REGISTRY = {
      "r50k_base" => {
        rank_file: File.join(DATA_DIR, "r50k_base.tiktoken"),
        pretokenizer: "gpt2",
        special_tokens: {"<|endoftext|>" => 50256}
      },
      "cl100k_base" => {
        rank_file: File.join(DATA_DIR, "cl100k_base.tiktoken"),
        pretokenizer: "gpt4",
        special_tokens: {
          "<|endoftext|>" => 100257,
          "<|fim_prefix|>" => 100258,
          "<|fim_middle|>" => 100259,
          "<|fim_suffix|>" => 100260,
          "<|endofprompt|>" => 100276
        }
      },
      "o200k_base" => {
        rank_file: File.join(DATA_DIR, "o200k_base.tiktoken"),
        pretokenizer: "o200k",
        special_tokens: {"<|endoftext|>" => 199999, "<|endofprompt|>" => 200018}
      }
    }.freeze
    private_constant :REGISTRY

    # The packaged encoding names — the single source error messages naming
    # what's available are built from (the same discipline
    # Native.pretokenizer_names / PretokenizerType::NAMES applies to
    # pretokenizer scheme names).
    NAMES = REGISTRY.keys.freeze

    # Encodings known by name but deliberately not packaged, keyed to the
    # reason a caller asking for one by name deserves to hear.
    UNPACKABLE_REASONS = {
      "p50k_base" => "its ranks are not dense (50256 is left free for <|endoftext|>), " \
        "and the rank loader rejects non-dense ranks"
    }.freeze
    private_constant :UNPACKABLE_REASONS

    class << self
      # The {rank_file:, pretokenizer:, special_tokens:} registered for a
      # packaged encoding name, or nil.
      def [](name)
        REGISTRY[name]
      end

      # Why `name` can't be packaged, or nil when there's no reason on
      # record (it's either packaged, or simply not one gigatoken knows of).
      def unpackable_reason(name)
        UNPACKABLE_REASONS[name]
      end
    end
  end
end
