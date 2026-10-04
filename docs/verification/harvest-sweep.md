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

## Rollout on the Mini (T20, T20b, T21)

Operator `kit.toml` (`~/.config/dwarves-kit/kit.toml`, chezmoi source in dotfiles): `[harvest] enable = true`, `sources = "claude devin"`; `hook_when_sweep_on` stays false. `wrap.distill` was left at `true` (see the implementation notes).

| Run | Command | Exit | Sessions (claude/devin) | Learnings | Candidates | Notes |
|-----|---------|------|-------------------------|-----------|------------|-------|
| T20 dry 1 | `--sweep --dry-run` (claude only) | 0 | 7 extracted | 25 | 7 | 7.5 min, first run |
| T20 dry 2 | `--sweep --dry-run` | 0 | 12/0 | 25 | 8 | no Devin session quiet inside the 6h first-run window |
| T20 dry 3 | `--sweep --dry-run --since <now-20h>` | 1 | 4/6 read | 17 | 4 | one Devin session failed (the model continued the transcript), then the probe failed on prose; fixed in #821 |
| T20 dry 4 | same, after #821 | 0 | 7/17 read, 20 extracted | 40 | 10 | 0 failed, 9 deferred, lag claude 2.6h |
| T20b real | `--sweep --since <now-20h>` | 0 | 7/17 read | 40 | 10 | 30 s (cache), gate-ledger line, no repo changed, `--status` prints the report line, `--flush-list` 40 rows |
| T21 scheduled | `launchctl kickstart gui/<uid>/mini.harvest-sweep` | 0 | 12/1 read | 17 | 5 | log `end rc=0`, report lint clean, heartbeat armed (`ping_count=1`), one flushed row archived |

Hand review (dry 4 and T20b): every Devin-sourced row traces to its `devin/<session>` with evidence from that session. No credential shape reached a ledger, sidecar, or report (one value redacted in `patterns.jsonl`). About a fifth of the learnings are generic or transient, and one (`macos-realpath-git-resolution`) records a mid-build state the code later reversed. Repo attribution follows the session cwd: Devin workers and lead sessions launched from ops-toolkit land in the ops-toolkit ledger even when they worked in a dwarves-kit worktree. Three of ten candidates carry a weak precedent match.

Token measurement (DEC-84): one real extractor call with `--output-format json` on an 11,970-char prompt used 10,052 input tokens (10 + 10,042 cache creation) and 1,521 output tokens. Claude Code's default system prompt is about 6,000 of those. A short `--system-prompt` cut input to 2,300 to 4,700 tokens but tripled output (6,200 to 9,400) and doubled cost on the same sessions, so the default stays. At the caps (20 extractions per run, 4 runs a day) that is about 2,400 calls, 24M input and 5M output tokens a month, twice DEC-68's 12.3M input estimate.

Flush round trip (T23): `--flush-list` listed 40 rows; `negctl-restore-wipes-uncommitted` (source `devin/rotated-freighter`) routed to the existing memory note that already records the lesson (`commit-before-negative-control`), then `--mark-flushed` flipped it (rc 0), a repeat exited 1, and the next scheduled run archived it. Driven by hand with the updated skill, not through a `/kit:wrap distill` session.

Hook stand-down: with the marker present, `harvest.sh --stop-trigger` exits before `harvest.py` (0 extractor calls); with a state dir that has no marker it reaches `harvest.py`. Other hosts carry no marker.

Unverified: the second consecutive scheduled run (T21 AC asks for two), and vps-mon `monitored` state until launchd discovery picks the plist up.
