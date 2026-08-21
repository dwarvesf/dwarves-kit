# Sub-goal 03: session-tools

**Merge policy:** auto
**Time budget:** 4-6 hours of loop work
**Proof:** run-table over a committed fixture transcript , `session-observe` prints its aggregate table, `session-recall` returns a point-lookup hit, `session-intel` prints a digest, and a unit test exercises the extracted `lib/session/parse-transcript.sh` directly. Named NCs: empty transcript = honest-zero (not a crash), malformed JSONL line skipped not fatal, missing transcript dir = clean error. COVERAGE-DELTA row (what the shared parser covers vs. each CLI's own remaining logic). Rung 3 (fresh-context recheck re-runs the fixture run-table; the tools parse untrusted transcript content).
**Design:** bearing (the shared-parser interface , what `parse-transcript.sh` returns to each caller , is a real design decision the design note explicitly left open; the executor's spec owes a `## Design` block for it)
**Depends on:** 01 (needs `lib/session/` to exist)
Model: sonnet
**Branch:** feat/kit-foldin-03-session
**PR base:** master (rebased after 01 merges)

## Outcome

The transcript/session tools live in the kit as `tools/session-observe/` (keeps its 3 bins , observe/semantic/vps-report), `tools/session-recall/`, and `tools/session-intel/` (keeps its own launchd deploy/ for the personal cron, deploy-follows-source). The ONE genuinely-duplicated routine , JSONL turn-parsing over the transcript schema , is extracted to `lib/session/parse-transcript.sh`, which both `session-observe` and `session-recall` call; the two CLIs stay SEPARATE (aggregate-stats vs. point-lookup are different mental models, per the design note). Transcript-dir and any personal path are opt-in env, no hardcoded ops path.

## Quality bar

`session-observe` and `session-recall` still feel like two different tools a user reaches for differently , the shared parser is invisible plumbing, not a merged CLI. The parser has ONE clear contract (what a parsed turn looks like) that both callers consume without special-casing. Honest-zero everywhere: an empty or partial transcript yields an empty/zeroed result with `n`, never a fabricated number or a stack trace.

## How to close the loop

- Move each tool to `tools/session-<name>/` (drop `cc-`), preserving its own tests/docs/pyproject where present (session-recall is Python).
- Extract the shared JSONL turn-parser: read both `cc-observe`'s single-pass scan and `cc-recall`'s `load()/_role()/_ts()`; design the ONE interface `lib/session/parse-transcript.sh` exposes (spec this , Design: bearing); rewrite both callers to use it.
- Adapter defaults: transcript dir via env (opt-in), no `~/workspace/<owner>` default; kit-internal paths repo-relative via `_repo_root()`.
- Commit a small fixture transcript (a few synthetic JSONL turns, NO real personal content) under `tests/fixtures/`.
- Run-table: observe table, recall lookup, intel digest, parser unit test , all over the fixture.
- NCs: empty transcript, one malformed line, missing dir.

Kit-adopted: record build + review + recheck via `bash lib/gate-ledger.sh`; `lane-classify` likely `normal`.

**Done =** all three CLIs produce correct output over the committed fixture, the shared parser has its own passing unit test AND both CLIs call it (no duplicate turn-parser remains , `grep` confirms), captured in `docs/proof/kit-foldin-session-tools.md`; honest-zero NCs pass.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-07 must retire the 3 ops-toolkit copies (cc-observe/recall/intel) once merged.
3. DECISIONS.md: record the `parse-transcript.sh` interface contract (the design decision) so SG-07 and future callers rely on it.
4. Report in records, EXIT.

## Scope edges

**In:** `tools/session-{observe,recall,intel}/`, `lib/session/parse-transcript.sh`, fixtures, their tests.
**Out:** `hooks/`, `agents/`, the ops retire (SG-07), `prose-rag` (a different tool, do not touch).
**Not:** merging observe+recall into one binary (explicitly rejected , keep two CLIs); adding new analytics beyond what the source tools did; renaming the 3 session-observe bins' user-facing verbs; pulling real transcripts into fixtures.

## Where to look

`ops-toolkit/tools/cc-{observe,recall,intel}/`, `dwarves-kit/lib/session/` (created by SG-01), `dwarves-kit/tools/ledger-observatory/` (the recent Python-in-kit precedent for pyproject + adapter-default shape), the design note's open-Q 1 (the merge resolution).

## PR body

Move the transcript tools into the kit as `tools/session-{observe,recall,intel}` (drop `cc-`), extracting the one duplicated JSONL turn-parser to `lib/session/parse-transcript.sh` that both observe + recall call; the two CLIs stay separate. Adapter defaults opt-in; honest-zero.

Verify: run-table (observe/recall/intel over a committed synthetic fixture) + parser unit test + honest-zero NCs. Proof: `docs/proof/kit-foldin-session-tools.md`. Stacked after #<SG-01 PR>.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-foldin/ROADMAP.md`.

## Notes
