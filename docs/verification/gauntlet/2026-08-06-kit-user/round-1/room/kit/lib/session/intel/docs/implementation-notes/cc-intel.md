# Implementation notes: cc-intel (cc-elevation-r2 sub-goal 06)

Delta from `_meta/megagoals/cc-elevation-r2/goals/06-scheduled-intel.md`.

## 2026-06-15 Deterministic heuristics, not Haiku
- The spec allowed Claude Haiku for synthesis + repeat-detect. Chose deterministic heuristics instead: normalized-name grouping for merge candidates, bash-command 3-grams for repeated sequences. Why: cheaper, fully testable with fixtures, no API dependency, and the output is a PROPOSAL a human reviews anyway, so LLM nuance buys little. The no-mini.ollama rule is satisfied trivially (no model at all).

## 2026-06-15 repeat-detect uses 3-grams, not single-command frequency
- Single-command frequency would flag `git status` / `ls` (noise). Consecutive bash-command 3-grams repeated >= N capture an actual repeated *sequence* worth an extract-workflow, which is the #5 intent. `--min` default 3.

## 2026-06-15 observe/sweep shelled out, degrade gracefully
- cc-intel shells out to `cc-observe report` + `repo-sweep run` (overridable via env for tests) rather than importing them (separate tools, own entry points). A missing/failing tool degrades that section to `_unavailable_`, never aborts the digest.

## 2026-06-15 Synthesis scope: ledger + GLOSSARYs (not cross-session transcripts)
- The cc-elevation "same concept across 3 sessions" idea needs cross-session history; the ledger stays small (flushed rows removed). So synthesis dedups across the durable homes that DO persist concepts (GLOSSARY headings) + the in-flight ledger. Cross-session-transcript concept mining is a possible follow-on (noted, not built).

## 2026-06-15 Live schedule is a deploy step
- The plist is provided + BTM-validated (`plutil -lint` + ProgramArguments[0] = the bare-name launcher), but `launchctl bootstrap` schedules a real recurring job on the Air (infra change), left to the operator per minimum-infra. The on-demand `run` is fully tested. The runbook has the recreate-from-zero sequence.
