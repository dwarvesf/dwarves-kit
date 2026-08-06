# Implementation notes: prose-rag (cc-elevation sub-goal 03)

Delta from `_meta/megagoals/cc-elevation/goals/03-prose-rag.md`.

## 2026-06-14 fastembed kept over model2vec (measured, not assumed)
- The plan said fastembed; I tested model2vec as a lighter alternative anyway. On this Air, model2vec cold-start was 589ms vs fastembed 254ms (model2vec's imports are heavier), and fastembed's bge embeddings are stronger. So fastembed wins on BOTH speed and quality here. Kept fastembed (bge-small, 384-d).

## 2026-06-14 Latency reality: hook is ~250ms/prompt, misses the <100ms aspiration
- The sub-goal quality bar said "<100ms on a warm index." The index query itself is a few ms, but the per-PROCESS cold start (fastembed import + ONNX model load) is ~250ms, and a Stop/UserPromptSubmit hook is a fresh process each prompt. So the hook adds ~250ms per prompt.
- Decision: ship it, but the auto-inject hook is OPT-IN (not auto-wired) with this caveat documented, and the index/query CLI (the high-value, latency-insensitive part) stands alone. A warm embedding daemon would get the hook under ~10ms but adds always-on infra; deliberately NOT built for v1 (minimum-infra). Noted as the future optimization.
- This is doubly relevant because sub-goal 01 (cc-observe) exists to find slow hooks; a 250ms RAG hook is a conscious, documented trade, not an oversight.

## 2026-06-14 Relevance floor calibrated from real measurement
- bge gives a baseline similarity ~0.50 even to unrelated text (gibberish scored 0.52 against the test corpus); genuine matches land 0.70-0.90.
- So the floors are query=0.55, hook=0.62 (NOT the 0.30 first guessed). Below ~0.55 is noise. Calibrated, then verified the real queries return 0.74-0.78 for on-topic notes.

## 2026-06-14 Brute-force cosine, no vec0 ANN index
- Retrieval is `vec_distance_cosine(embedding, query)` over a plain table, ORDER BY LIMIT k. The corpus is 4082 chunks; brute force is fast and avoids depending on sqlite-vec's vec0 MATCH/KNN syntax. If the corpus grows past tens of thousands of chunks, switch to a vec0 virtual table.

## 2026-06-14 Index build is slow (offline)
- Embedding the real corpus (4082 chunks: til + research + ledger) took ~8 min via ONNX on CPU. It is an offline, infrequent operation (re-run when the corpus changes), so this is acceptable. Query against the built index is fast.

## 2026-06-14 Invocation needs the uv venv; hook wiring uses .venv/bin/python
- The tool imports fastembed + sqlite-vec, so it runs under the uv project venv. Tests use `uv run --project <dir> python bin/prose-rag`. For the hook, wire `~/.claude` to call `<tool>/.venv/bin/python <tool>/bin/prose-rag hook` (after `uv sync`), NOT `uv run` (avoids ~100ms uv overhead on top of the model load). Runbook covers `uv sync` on deploy. `uv.lock` is committed; `.venv/` is gitignored.

## 2026-06-14 Corpus scope (open knobs left OFF)
- Corpus = til + ops-toolkit/research + _meta/learned-ledger.md. The Obsidian vault and the Voyage cloud embedder stay OUT per the sub-goal's open-knobs (privacy: nothing leaves the Air). Flippable via `--corpus` / `PROSE_RAG_MODEL` if Han decides later.
