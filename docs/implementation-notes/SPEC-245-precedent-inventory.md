# Implementation notes: SPEC-245 precedent inventory surface

Delta from the spec only. Decisions already in the spec's Decision Log are referenced, not repeated.

## 2026-09-06 Before build

- The four research files under `docs/research/` are session scratch. `architecture.md` was tracked from an earlier spec and got overwritten by the research agent; restored with `git checkout --`, and the three untracked reports stay out of the commit.
- `tests/test-meta.sh` pin at 2079-2087 (SPEC-068) reads `precedent.sh find` and `-x lib/precedent.sh`. Rewritten in TASK-001 to `precedent find` and `-x bin/precedent`; the SPEC-068 label in the message is kept so the test history stays greppable.

## 2026-09-06 15:40 TASK-001 build

Context: moved `lib/precedent.sh` to `lib/precedent/precedent.sh`, added `bin/precedent`, and added flag parsing to `find` per SPEC-245's Technical Design.

Decision: a positional `[max]` after the words forces the records surface (ignoring the `all` default) unless the caller also passes `--surface` explicitly, and it doubles as the limit. Why: the spec calls the positional form "records-only calls (existing callers)"; the parity acceptance test (`find "spec drift" 3` must byte-match the pre-move script) only holds if the legacy call shape never gains the summary line an `all` surface would add. Alternatives: default surface stays `all` even with a positional max, appending the placeholder summary line, rejected because it breaks the stated byte-parity criterion. Impact: `find "<words>" [max]` is unchanged for every existing caller; `find "<words>" [max] --surface all` (untested combination) would still honor the explicit flag and add the summary. Open question: none, this reading matches both acceptance tests.

Decision: `--quiet` and `--json` are parsed and accepted (never error) but have no visible effect yet, since the only thing they would govern (the inventory digest) is the Phase-1 placeholder (no `inventory.py`). Why: SPEC-245 phases the real quiet/json contract into TASK-003/004 against the real inventory scan; wiring them against an empty placeholder would be work redone at TASK-004. Impact: none observable in TASK-001; TASK-004 must wire these into `_inventory_find` and the `all` summary path.

Decision: `--explain <label>` with no `inventory.py` present always prints `explain: no file for <label>` and exits 1, matching Edge Case 6 verbatim (a label that resolves nowhere). Why: with no inventory scan built yet, no label can ever resolve, so the "not found" branch is the only truthful placeholder response. Impact: TASK-003 replaces this with a real dispatch to `inventory.py --explain` once it exists; the placeholder path stays as the `inventory.py`-absent fallback.

Deviation: fixed two test files the task list did not name, `tests/test-hooks.sh` (the SPEC-068 behavioral suite, lines 220/225) and `tests/test-ledger-durability.sh` (line 18), both of which called `lib/precedent.sh` by its old path. Why: the `git mv` in this task breaks them outright (file not found); leaving them broken would be a real regression the spec's own "no regressions in existing functionality" criterion rules out, even though only `test-meta.sh` and `test-bin-forwarders.sh` were named. Impact: both suites are green again (`test-hooks.sh` 497/497, `test-ledger-durability.sh` 37/37).

Deviation: regenerated `docs/FEATURES.md` (`bash lib/registry/feature-registry.sh generate docs/FEATURES.md`). Why: the freshness pin (SPEC-219) was already failing at `dd7f32b`, before any TASK-001 edit, because the SPEC-245 doc itself references several commands and `hooks/harvest.py` in its own References line, which shifted the generator's per-command spec/test counts; the drift was verified against `e7f5fee` (fresh) and `dd7f32b` (stale) via `git archive`. Regenerating touches no command, agent, skill, or hook, and is the sanctioned way to clear this class of drift (`CLAUDE.md`: "docs/FEATURES.md is generated ... never hand-edited"). Impact: `tests/test-meta.sh` is 829/829 green; content change is confined to derived counts, no new rows.
