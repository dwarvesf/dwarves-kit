# prose-rag

Semantic search over your own prose corpus (a knowledge base, research notes, a
learned-ledger), so a prompt can pull in the relevant notes you have already
written. Fully local, no cloud embedder.

Folded in from ops-toolkit `tools/prose-rag` (2026-07-11; the kit-foldin "stays
personal" disposition was overruled: the engine is generic, only the corpus is
personal). The corpus is CONSUMER CONFIG: set `PROSE_RAG_CORPUS` to colon-separated
dirs/files (e.g. `~/notes:~/research:~/ledger.md`); unset means an empty corpus.
Enabled via the `prose_rag` module (`bash install.sh --with prose_rag`): wires the
dormant UserPromptSubmit recall hook (`hooks/prose-rag.sh`, activates only with
`PROSE_RAG_INJECT=1`) and the `prose-rag` CLI shim (stable entrypoint
`bin/prose-rag`).

**Rust engine only.** The original Python/fastembed engine was dropped at the fold
(one engine, one truth): the Rust engine indexes a 4.6k-chunk corpus in 0.63s on
one core vs 8+ minutes, refreshes incrementally in 0.04s, answers a warm hook in
~29ms vs ~250ms, and ships as a 4.9MB static binary instead of a Python venv +
ONNX runtime. Embeddings: model2vec static (potion-retrieval-32M, 512-d); index at
`~/.claude/prose-rag/index.bin`; sim floors query 0.32 / hook 0.40. Port story +
candle/Metal post-mortem: `docs/implementation-notes/rust-port.md`. Original design
records: `SPEC.md`, `docs/implementation-notes/03-prose-rag.md` + `03-rag-autoinject.md`.

## Build (once per machine)

```bash
cd lib/prose-rag/rust
cargo build --release                       # binary at target/release/prose-rag
cp target/release/prose-rag ../bin/prose-rag-rs   # where the stable entrypoint looks first
prose-rag index                             # first run downloads potion-retrieval-32M (~124MB), then ~1s
```

The stable entrypoint (`bin/prose-rag`) execs `lib/prose-rag/bin/prose-rag-rs` (or
the cargo target dir); until the binary is built, `hook` exits 0 (a recall hook
must never break a prompt) and other commands print the build hint.

## Use

```bash
prose-rag query "claude code hook latency"      # rank relevant prior notes
prose-rag query "..." --k 8 --floor 0.4 --json
prose-rag index                                  # incremental: only changed files re-embed
prose-rag index --full                           # force a full rebuild
```

## Opt-in, recall-gated hook

A UserPromptSubmit hook injects the top matches, but only when it earns its keep:

- **Opt-in master switch.** The hook is inert unless `PROSE_RAG_INJECT=1` is in the environment, so you can wire it and leave it dormant until you flip the env. `--force` bypasses the switch (testing).
- **Recall gate.** Even when on, it only fires on recall/research-phrased prompts ("have I written...", "did I already...", "what did I conclude..."). Operational prompts (edits, git, "fix this") are skipped first, so they pay ~4ms.

```json
{ "type": "command", "command": "/abs/path/to/prose-rag hook" }
```

## How it works

Markdown is chunked by heading and embedded with model2vec static embeddings: tokenize, look up each token's pre-distilled vector (mmap'd table, only touched rows are read), mean, L2-normalize. A query embeds the same way and ranks all chunks by dot product (vectors are normalized, so dot == cosine). No transformer runs at inference; that is why indexing is seconds, not minutes. Retrieval quality was validated against the bge engine on real recall queries (top hits agree; see rust-port.md).

The index is bincode with a per-file FNV-1a content hash, so `index` re-embeds only changed files and prunes deleted ones. The model download is pinned to an exact upstream revision (`MODEL_REV` in main.rs); re-pin deliberately to upgrade.

## Tests

```bash
cd tools/prose-rag/rust
cargo test --release        # 9 unit tests: chunker (+boundaries/windowing), fnv, gate, search, index roundtrip/corruption guard, gather parity/symlink guard, f16+f32 row decode
bash tests/smoke.sh         # CLI checks: index/query/hook end-to-end, incremental rerun, deletion prune, clobber guard, corpus-config guard, windowed-tail retrieval
```

The legacy Python suite is `tests/smoke.sh` at the tool root (11 checks, Python engine only).

## Limits

- Static embeddings trade ~10-15% retrieval quality vs a transformer; validated as acceptable for this corpus and use case. If it ever disappoints, the fallback path is ort+CoreML (noted in rust-port.md), not a return to the 8-minute index.
- Floors are model-specific: noise sits <=0.26, real matches 0.41-0.58. If the model changes, recalibrate with negative-control queries.
- Local-only by design: the Obsidian vault and cloud embedders are off (privacy). The hook never downloads: on a cold model cache it silently skips (only `index`/`query` fetch the model).
- Corpus + db are env/flag-overridable (`PROSE_RAG_DB`, `--corpus`); the model is baked (changing it invalidates every stored vector).
- **`PROSE_RAG_DB` is shared with the legacy Python engine** (which defaults to `index.db`, sqlite). Pointing the Rust engine at a non-bincode file makes it refuse loudly rather than overwrite; `--full` is the explicit consent to rebuild over it.
