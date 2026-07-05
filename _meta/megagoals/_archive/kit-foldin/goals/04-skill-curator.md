# Sub-goal 04: skill-curator

**Merge policy:** auto
**Time budget:** 2-3 hours of loop work
**Proof:** run-table , the tool's existing 11 tests green AFTER the move (identical count), PLUS an adapter-default negative control: with `CC_SI_MEMORY_LEDGER` unset, the tool raises a clean error at the call site (mirrors the ledger-observatory adapter fix), never silently writes to the old ops-toolkit path. COVERAGE-DELTA row. Rung 2 (named NCs; a wholesale move of tested code, no new surface).
**Design:** obvious (wholesale subtree move + one env-default flip; the design note confirmed exactly one hardcoded line)
**Depends on:** none (self-contained subtree in `tools/`)
Model: sonnet
**Branch:** feat/kit-foldin-04-skill-curator
**PR base:** master

## Outcome

The skill self-improvement loop (was cc-self-improve, 22 files / 11 tests) lives at `dwarves-kit/tools/skill-curator/` , renamed off `self-improve` (which reads as recursive-on-itself) to name its function: it curates/improves skills. Its one hardcoded personal default (`lib/surface.sh` `CC_SI_MEMORY_LEDGER` -> `$HOME/workspace/tieubao/ops-toolkit/_meta/learned-ledger.md`) is flipped to opt-in: unset = a clean error at the call site, never a silent write. No hardcoded Hermes host exists (confirmed); the personal deploy runbook stays ops-toolkit-side (deploy-follows-source). **The subtree's embedded `skills/skill-review/SKILL.md` is PROMOTED to top-level `dwarves-kit/skills/skill-review/`** (per Decision 2, `skills/*/SKILL.md` is loader-mandated top-level, same class as `agents/` , left nested under `tools/` it would silently never install for any consumer). SG-02 generalizes `install.sh`'s skill-copy step to a `skills/*` glob loop that picks it up; if that has not landed yet, the skill dir still sits in the right place for whenever it does.

## Quality bar

The move is invisible to behavior , all 11 tests pass unchanged. The tool is now agent-generic: it runs against whatever skill dir + ledger the consumer points it at, with no assumption it lives in ops-toolkit. A consumer who never sets the ledger env gets a clear "set CC_SI_MEMORY_LEDGER" error, not a write into a path that does not exist on their machine.

## How to close the loop

- Move the tool subtree from `ops-toolkit/tools/cc-self-improve/` (57 files total, NOT 22 , "22" was only the code-file count) to `dwarves-kit/tools/skill-curator/`, WITH these exclusions/rewrites (else the Done grep below fails):
  - **`deploy/` stays ops-toolkit-side** (the `mini.cc-curator.plist` + `cc-curator-runbook.md` are personal deploy artifacts, deploy-follows-source per Assumption 7) , do NOT move it.
  - **`RUNBOOK.md` + `MANUAL.md` hardcode `~/workspace/tieubao/ops-toolkit/...`** and are NOT under `deploy/` , rewrite those paths to be generic (or strip the personal examples) as part of the move.
  - Cross-repo history-preservation is best-effort: try `git format-patch`/`git subtree split` replayed via `git am` for real per-commit history before falling back to a single-commit move (advisor P6 #4); log which was used.
- Rename internal `cc-si`/`cc-self-improve` identifiers to `skill-curator` where they are user-facing; keep internal var names if renaming risks the tests (surgical).
- Flip `lib/surface.sh:9`: `CC_SI_MEMORY_LEDGER` default from the hardcoded ops path to empty; add a guard that errors clearly if unset when the ledger is actually needed.
- Move the embedded `skills/skill-review/` out of the tool subtree to top-level `dwarves-kit/skills/skill-review/` (it is loader-mandated top-level); confirm nothing in the tool hardcodes the old nested path.
- Run the tool's own 11-test suite; capture the run-table (identical pass count).
- NC: unset `CC_SI_MEMORY_LEDGER`, invoke the ledger path, assert the clean error (not a silent write / not a crash with a confusing trace).
- `grep -r 'workspace/tieubao' tools/skill-curator/` must be empty.

Kit-adopted: record build + review via `bash lib/gate-ledger.sh`; `lane-classify` likely `normal`.

**Done =** the 11 existing tests pass at identical count post-move AND the unset-ledger NC produces a clean error, captured in `docs/proof/kit-foldin-skill-curator.md`; no ops-toolkit path remains in the moved subtree.

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: SG-07 retires `ops-toolkit/tools/cc-self-improve` (status=moved -> skill-curator).
3. DECISIONS.md: record the rename map (cc-self-improve -> skill-curator) + the env-default flip.
4. Report in records, EXIT.

## Scope edges

**In:** `dwarves-kit/tools/skill-curator/` (the moved subtree), the one env-default flip, promoting `skill-review` to top-level `dwarves-kit/skills/skill-review/`.
**Out:** `lib/`, `hooks/`, `agents/`, other tools, `install.sh` (SG-02 owns the skill-copy loop); the ops retire (SG-07); the `deploy/` subtree (STAYS ops-toolkit-side, deploy-follows-source , do not move it).
**Not:** refactoring the self-improvement logic while moving it; adding features; renaming internal vars that would churn the 11 tests; touching the Hermes-adjacent naming (it is generic `claude -p`, leave it); editing `install.sh` (that is SG-02's , just place the skill dir).

## Where to look

`ops-toolkit/tools/cc-self-improve/` (esp. `lib/surface.sh`), `dwarves-kit/tools/ledger-observatory/` (the adapter-default precedent from SG-05K), the design note's open-Q 4 (RESOLVED: clean, one line).

## PR body

Move cc-self-improve wholesale to `tools/skill-curator` (renamed off "self-improve") + flip its one hardcoded `CC_SI_MEMORY_LEDGER` default to opt-in (clean error when unset). No Hermes host hardcode exists.

Verify: existing 11 tests green at identical count; unset-ledger NC = clean error. Proof: `docs/proof/kit-foldin-skill-curator.md`.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-foldin/ROADMAP.md`.

## Notes
