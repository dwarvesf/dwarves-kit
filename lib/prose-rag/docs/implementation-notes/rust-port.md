# Implementation notes: prose-rag Rust port

Delta log from the Python original (`bin/prose-rag`). The port exists because a full
`index` run pegged 3-4 CPU cores for 8+ minutes (fastembed/ONNX, no thread cap, full
re-embed every run) and made the Air unusable.

## 2026-07-11 00:20 Final engine: model2vec static embeddings (potion-retrieval-32M)

Context: the port only pays off if it changes what computes, not what language runs.
Decision: swap the bge-small transformer for model2vec static embeddings
(minishlab/potion-retrieval-32M, dim 512): token lookup + mean + L2 normalize, no
transformer at inference. mmap the 123MB table and convert only the rows a text touches.
Why (measured): full 4,635-chunk index 0.63s on ONE core (was 8+ min at 286-420% CPU);
no-op incremental refresh 0.04s; hook 28.6ms warm (was ~250ms); 4.9MB static binary.
Quality: top hits agree with bge on all 4 real recall test queries (1P quota 4/5 source
overlap, CF workers 3/5); acceptable for the "point me at my prior notes" use case.
Alternatives rejected: see the candle post-mortem below; ort+CoreML EP (untested, heavy
build, kept as fallback if potion quality ever disappoints).
Impact: sim floors recalibrated (noise <=0.26, real matches 0.41-0.58): query default
0.55 -> 0.32, hook 0.62 -> 0.40. First run downloads ~124MB from HF; loads are
cache-first (hf-hub's online get() does a ~450ms etag check per file even when cached).

## 2026-07-11 00:20 Post-mortem: candle + Metal was tried first and lost to Python

The original port plan (bge-small via candle with Metal kernels, "GPU so CPU stays idle")
was built and benchmarked. Verdict: candle 0.9.2's Metal path runs BERT attention at
seq~512 in ~9-11s per 32-text batch (f16; f32 was ~7x worse) => full corpus ~15+ min,
WORSE than the Python/ONNX CPU baseline. Two false trails documented for next time:
- What looked like a Metal deadlock (`waitUntilCompleted` in `sample`, 0% CPU) was just
  a legitimately slow GPU wait. Neither `device.synchronize()` per batch nor fixed-shape
  padding was the issue.
- Synthetic benchmarks lied at first: uniform short texts made batches cheap enough to
  hide the problem; the real corpus (mixed 450-512 token chunks) exposed it.

## 2026-07-11 00:20 Incremental indexing (new capability, not in the Python original)

Per-file FNV-1a content hash in the index; only changed/new files re-embed, vanished
files are pruned; `--full` forces a rebuild. Index format is bincode at
`~/.claude/prose-rag/index.bin` (the Python sqlite-vec `index.db` is left untouched; no
migration, first Rust run builds fresh).

## 2026-07-11 00:20 Parity choices

- Chunker, CLI contract (index/query/hook + flags), recall markers: ported verbatim.
- Query embedding unprefixed (parity with the Python tool's behavior).
- `PROSE_RAG_MODEL` env dropped: a model change invalidates every stored vector, so it
  is a code change now. `PROSE_RAG_DEVICE`/thread knobs dropped: nothing to tune, the
  engine is one core for fractions of a second.
- sqlite-vec dropped: brute-force dot product over ~5k normalized vectors is
  microseconds; a vector extension earns nothing here.

## 2026-07-10 16:00 Interim fix on the Python original (superseded by the port)

`PROSE_RAG_THREADS` (default 4) caps fastembed/ONNX intra-op threads in
`bin/prose-rag`; the deployed cc-elevation snapshot was hand-patched with the same
change (drift-toward-repo) because redeploy pulls from origin/main and the sibling
session's repeated uncapped runs were pegging the machine mid-development.
