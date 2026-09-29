# Proof of done: harvest sweep, phase 1 (SPEC-357)

Verdict: PASS for the build through T19 plus the flush verbs (T22). The live rollout tasks (T20, T20b, T21, and the companion tasks T23 in dotfiles and T24 in ops-toolkit) are not part of this proof: [UNAVAILABLE: the sweep ships disabled (`harvest.enable = false`) and its first real run is the operator-reviewed hand dry run on the Mini, T20].

## Acceptance criteria -> confirmation

| Area | How proven | Result |
|------|------------|--------|
| Sources, cursor, selection, lag (AC1, AC6, AC25, AC26) | `tests/test-harvest-sweep.sh` cursor and selection blocks, including the 48h outage with three capped runs and nothing dropped | PASS |
| Extractor safety and failure classes (AC4, AC5, AC5b, AC22, AC27, AC30) | stub extractor tests: `--tools ""`, `--strict-mcp-config`, `--no-session-persistence` in argv, limit hold, probe, auth stop, quarantine and lift, atomic cache | PASS |
| Sanitizing and redaction (AC9, AC22) | redaction fixtures built at runtime, second redaction pass after the character strip, `stage1.log` mode 0600 with ids and counts only | PASS |
| Ledgers, sidecar, dedup (AC2, AC3, AC11, AC17, AC29) | repo-slug ledgers, `rows.jsonl` sidecar, no file created in a repo, flush round trip, archive dedup | PASS |
| Patterns and annotator (AC7, AC15, AC18, AC23) | lead-group counting, fuzzy floor, argv-only subprocesses with a metacharacter fixture, code home over prose home, PROSE-ONLY bullet | PASS |
| Report, lint, rc contract (AC10, AC12, AC31) | `sweep_report` lint flag fixtures, rc mapping, pruning by age | PASS |
| Config, launcher, installer, wrap knob (AC8, AC13, AC19, AC21) | host-marker gate, launcher bridge arguments (disabled host never calls the bridge, stale report passes `-`), install and uninstall chain, `wrap.distill = "harvest"` | PASS |

Every task's negative controls were run with `lib/gate/negctl.sh` after its commit and went red, then green. Each group was checked by a fresh verifier that re-ran one control per task. The per-task record is in `docs/implementation-notes/harvest-sweep.md`.

## Confirmation run-table

| Command | Exit | Result |
|---------|------|--------|
| `bash tests/test-harvest-sweep.sh` | 0 | 593/593, all harvest sweep tests passed |
| `bash tests/test-kit-foldin-hooks.sh` | 0 | 97/97 |
| `bash tests/test-meta.sh` | 0 | 886/886, FEATURES.md fresh |
| `bash tests/test-install-modules.sh` | 0 | 42 passed, 0 failed |
| `bash tests/test-hooks.sh` | 0 | 709/709 (verifier run at 1bbeeefc; the later commits add tests only) |
| `bash tests/test-wrap.sh` | 0 | 1486 passed (verifier run at 1bbeeefc) |

## Run detail

```
Command: bash tests/test-harvest-sweep.sh
Exit: 0
Verdict: All harvest sweep tests passed.

Command: bash tests/test-kit-foldin-hooks.sh
Exit: 0
Verdict: All kit-foldin hooks tests passed.

Command: bash tests/test-meta.sh
Exit: 0
Verdict: All meta tests passed.

Command: bash tests/test-install-modules.sh
Exit: 0
Verdict: == 42 passed, 0 failed ==
```

NEGATIVE CONTROL example (gap test 3, commit 40901380): dropping the launcher's report mtime guard made the stale-report test fail; restoring it passed. Every other control is listed per task in the implementation notes.

## Rollback

The sweep ships off: `harvest.enable = false`, `harvest.sources = "claude"`, no plist installed, and `wrap.distill` keeps its current value until an operator sets `"harvest"`. Rollback is a revert of this PR. On a host where the sweep was installed, `install --uninstall` removes the plist, the rendered settings and the host marker, which turns the per-session harvest hook back on; kit state under `~/.claude/dwarves-kit/state/harvest/sweep/` is kept and the uninstall prints the purge command.
