# Proof of done , cc-recall (token-optim-v3 SG-03)

Read-only, lossless, turn-grouped recall over Claude Code transcripts. Ports pi-vcc's
`vcc_recall`: structure-preserving substring search over raw `~/.claude/projects/*.jsonl`.

## Acceptance criteria (from goal 03-cc-recall.md)

| # | Criterion | Met |
|---|-----------|-----|
| 1 | A query returns a known-present decision from a seed transcript, grouped by turn | yes |
| 2 | Result carries turn context + match indicator (not a naked line) | yes (`── turn N · role · ts`, `»…«`) |
| 3 | Negative control (absent term) returns empty, clean exit | yes (exit 0, no stdout) |
| 4 | Read-only , never mutates a transcript | yes (sha256 unchanged, test) |
| 5 | Fast enough for mid-session use (< 1-2s on a real project) | yes (0.02s, 4 transcripts) |
| 6 | Run-table records hit + negative control + latency | yes (below) |

## Implementation

- `cc_recall.py` , stdlib search module. `load()` (shared JSONL parser with SG-01),
  `searchable_text()` (prose + thinking + tool inputs + tool results), `search()`
  (case-insensitive phrase substring, conversation order preserved), `render()`
  (turn-grouped snippets with `»match«` indicators), `resolve_files()` (file/project/all).
- `bin/cc-recall` , executable CLI wrapper.
- `fixtures/seed.jsonl` , synthetic seed (zero PII), shared with SG-01.
- `tests/test_recall.py` , 7 stdlib `unittest` cases.

## Confirmation run-table

| Check | Method | Result |
|-------|--------|--------|
| Tests | `python3 -m unittest discover -s tests` | 7/7 OK |
| Known-decision hit | query "manual backoff loop because we avoid" | turn 2, assistant (exact) |
| Cross-block match | query "src/fetch_client.py" (only in tool I/O) | 3 turns |
| Turn-grouped + indicator | render contains `── turn` and `»…«` | yes |
| Negative control | query "string-that-does-not-exist-zzz" | empty stdout, exit 0 |
| Read-only | sha256(seed) before vs after a CLI search | unchanged |
| Determinism | two identical CLI runs | byte-identical |
| Latency (real) | `--project <real 4-transcript project>` | **0.02s** |

## Recorded run (captured 2026-06-29, exit codes verbatim)

```
Command: python3 -m unittest discover -s tests
Ran 7 tests in 0.071s
OK
Exit: 0

Command: ./bin/cc-recall "manual backoff loop because we avoid" --file fixtures/seed.jsonl
── turn 2 · assistant · 2026-06-29T09:00:02.000Z ──
  Going with a »manual backoff loop because we avoid« adding a new dependency. Decision: cap retries at 5 ...
Exit: 0

Command: ./bin/cc-recall "string-that-does-not-exist-zzz" --file fixtures/seed.jsonl
Exit: 0        # empty stdout (stderr: "no matches"); the negative control

Command: /usr/bin/time -p ./bin/cc-recall "the" --project <real 4-transcript project> --limit 5
real 0.02
Exit: 0
```

NEGATIVE CONTROL: the query "string-that-does-not-exist-zzz" is absent from the transcript;
`test_negative_control_cli_clean_exit` asserts empty stdout + exit 0. A bug that printed a
phantom hit (or a wrong all-turns match) would make it RED. Verdict: PASS.

## Rollback

Additive, read-only tool. No persistent state, no daemon, no DB, no host config. Rollback =
`git revert` the commit (or delete `tools/cc-recall/`); the tool only ever READS transcripts,
so there is nothing on disk to undo. The `seed` in `seed.jsonl` is a TEST FIXTURE, not a
data-store seed.

## Reproduce

```
cd tools/cc-recall
python3 -m unittest discover -s tests              # 7/7 OK
./bin/cc-recall "backoff" --file fixtures/seed.jsonl
./bin/cc-recall "zzz-absent" --file fixtures/seed.jsonl; echo "exit=$?"   # empty, exit 0
```

## Honest limits

- Phrase substring match (case-insensitive), not semantic. For meaning-based recall use
  `prose-rag`; this is the exact, lossless, structure-preserving complement.
- Default project resolution derives the slug from cwd; pass `--project`/`--all`/`--file`
  to widen. No fuzzy ranking , hits are returned in conversation order, capped by `--limit`.
