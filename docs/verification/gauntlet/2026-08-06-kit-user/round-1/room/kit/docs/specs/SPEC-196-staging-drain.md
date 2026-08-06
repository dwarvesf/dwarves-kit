# Spec: `learn drain`, staging review render (harness-loop sub-goal 06)

Generated: 2026-07-12
Status: VALIDATED
Lane: full (`bash lib/classify/lane-classify.sh classify --files "lib/learn/drain.py
lib/learn/drain.sh lib/learn/staging-format.py lib/learn/learn.sh tests/test-learn-drain.sh
docs/specs/SPEC-196-staging-drain.md" "..."` -> `full`, hard-gate flag `kit-machinery`: any
`lib/` edit in this kit-adopted repo is full lane by contract, independent of size)
Design: obvious (goal file `_meta/megagoals/harness-loop/goals/06-staging-drain.md`: "render +
a dated move within one file; ADR-0034 names the verb"); think/design/design-critique/
design-record recorded SKIPPED per that line, gate-ledger rid `loop-06-staging-drain`
Relates-to: `docs/decisions/0034-harness-loop-taxonomy.md` decision 1 (the `learn` subsystem,
the `learn drain` verb name locked there), `hooks/backlog-stage.py` (the block grammar this
reads), `lib/board/bin/add-backlog` (the promote/reject consumer of the same file, unchanged)

## Problem

`hooks/backlog-stage.py` auto-stages backlog candidates from session transcripts into
`_meta/backlog-staging.md` as `## [staged] <title>` blocks. On a live corpus this file grows
fast (69 staged candidates on the real ops-toolkit copy as of this writing) and reading it is
the only way today to answer "what do I promote?" -- there is no render, no age signal, no
grouping. `lib/learn/learn.sh`'s `drain` verb currently REFUSES (`echo "learn drain: not yet
implemented -- ships in SPEC-196" >&2; exit 1`), the stub ADR-0034/SG-04 left in place. Left
alone, staged candidates never get old enough to demand attention and never get review; the
5-minute "what do I promote?" ritual the mega-goal's outcome names does not exist.

## Solution shape

`learn drain` (wired through `bin/learn drain` -> `lib/learn/learn.sh` -> `lib/learn/drain.sh`
-> `lib/learn/drain.py`) is a pure read + render, with exactly ONE write:

1. **Shared parse helper** (`lib/learn/staging-format.py`, landed here since SG-05 had not
   landed it first, per the sub-goals' shared-fixture rule): the ONE definition of a
   `## [<state>] <title>` block's boundary + field grammar (`- Field: value` lines), plus
   `source_date()`/`age_days()` helpers reading the `Source: session YYYY-MM-DD` field. Mirrors
   (does not replace) `lib/board/bin/add-backlog`'s private `parse_staging()` -- that reader is
   settled and out of this sub-goal's touch list; a future cleanup can point it at this module.
2. **Expiry** (`drain.py::expire_stale`): every `[staged]` block whose `Source` date is more than
   `--days` (default: the `DEFAULT_EXPIRE_DAYS = 30` constant in `drain.py`, a plain Python
   constant, never a `kit.toml` key per ADR-0034's pin -- this is what keeps SG-06 file-disjoint
   from SG-05's `kit.toml` edit) old gets its header token relabeled in place, `## [staged]` ->
   `## [expired]` (same idiom `add-backlog` already uses for `[rejected]`/`[promoted <id>]`):
   content, position, and every other block stay byte-identical; nothing is deleted. The write is
   guarded by a blocking exclusive `fcntl.flock` on a sibling `<staging>.lock` file, the same
   idiom `hooks/harvest.py`'s post-#226 dedup-on-append fix uses for the learned-ledger (adapted
   here to the staging file: open/create the lock, acquire, read + mutate + write, release in
   `finally`).
3. **Render** (`drain.py::render`): numbers the CURRENTLY-staged blocks 1..K in file order --
   the exact numbering `lib/board/bin/add-backlog`'s `board promote <n>` already reads (it
   enumerates `[b for b in blocks if b["state"] == "staged"]`, 1-based) -- so a number `learn
   drain` prints is always safe to hand straight to `board promote <n>`. Groups those numbered
   candidates by `Home:` (alphabetical), age-sorted oldest-first within each group (unknown-age
   blocks last), one line per candidate: `<n>. <title>  <age>d  <tags>  <evidence>` (evidence =
   the `Source:` field, the candidate's provenance). No forced truncation (matches
   `lib/stats/src/stats/render.py::render_terminal`'s stated policy: a table/list that outgrows
   the phone-legible 32-cell heuristic is a signal to look elsewhere, not a reason to truncate
   silently).

`board promote`'s existing filter (`state == "staged"`) already excludes `[expired]` rows from
its numbered list -- no code change needed in `lib/board/bin/add-backlog` for the "expired rows
unselectable" requirement.

## Scope edges

**In:** the drain render, the 30-day expiry-to-`[expired]` move (constant + `--days` override),
the shared staging-block parse helper, tests.
**Out:** promotion logic changes, staging WRITE paths (`hooks/backlog-stage.py`,
`stats --propose`), notification/nudge hooks, a TUI, an HTML drain surface, auto-promote of any
kind. `lib/learn/propose*` (SPEC-195, SG-05) is untouched.

## Test plan

1. **Render on real-shaped data**: run `learn drain` against a COPY of the real 69-candidate
   `~/workspace/<owner>/ops-toolkit/_meta/backlog-staging.md` (never the live file); capture raw
   text output + a freeze-PNG.
2. **Expiry NC**: a fixture with a 31-day-old `[staged]` row and a 5-day-old `[staged]` row;
   after one drain run the 31d row is `[expired]`, the 5d row is still `[staged]`; a byte-diff of
   before/after proves only the header token changed on the expired block (move, not delete); a
   second immediate run changes nothing (idempotent -- `[expired]` is no longer eligible).
3. **Promote-unchanged NC**: `lib/board/bin/add-backlog`'s existing fixture-backed promote/reject
   flow still passes unmodified, and an `[expired]` row never appears in its numbered list.
4. **Numbering-parity NC**: the index `learn drain` prints for a candidate matches the index
   `board promote` (list mode) prints for the same candidate on the same file.

## Verification

```
bash tests/test-learn-drain.sh
bash tests/test-weekend-batch.sh      # sibling lib/learn/ suite, unaffected
bash tests/test-bin-forwarders.sh     # dispatch-chain census (drain no longer refuses)
bash tests/test-hooks.sh
bash tests/test-meta.sh
```
