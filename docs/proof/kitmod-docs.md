# Proof of done, kit-modularity SG-06: docs

**Change:** PHILOSOPHY.md gains a "Toolbox, not appliance" principle (the a-la-carte model +
the anti-goal stated plainly) plus two required companion paragraphs (Multi-agent future,
Team mode: parked-not-absent). README.md's lead and Install section are rewritten for a
first-time adopter: lead with the standalone `<subsystem>` shell commands + the "install
spine, opt into modules" model, and the Install section now documents every `--with` module
name (previously undocumented anywhere in the repo). The bulk of the deliverable is the F-bar
doc audit below: every installable/fireable unit from the merged SG-01..04 surface, mapped to
its usage doc + firing point, with the one real gap (a naming ambiguity) called out honestly
and the one flagged inline-doc-only case (`lib/ledger/ledger.sh`) explicitly justified rather
than papered over with a new file.

## 1. Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| AC1 | PHILOSOPHY carries toolbox-not-appliance + stated anti-goal | PASS |
| AC2 | PHILOSOPHY carries the multi-agent-future paragraph (shell vs authoring surface) | PASS |
| AC3 | PHILOSOPHY carries the team-mode-parked paragraph (Decision C, named tripwire) | PASS |
| AC4 | README lead leads with standalone commands + spine/opt-in model | PASS |
| AC5 | README documents every `--with` module name (net-new; was undocumented) | PASS |
| AC6 | F-bar audit: one row per installable/fireable unit, zero unjustified gaps | PASS (35 rows, 0 unjustified gaps) |
| AC7 | NC: delete a module's usage doc -> audit mechanism flags it -> restore | PASS |
| AC8 | Re-grep live `.py`/`.sh`/README surfaces for stray `ledger-observatory` labels | PASS (0 live-label hits; all remaining hits are frozen provenance/history text) |
| AC9 | Full test-meta.sh suite (structural/cross-link checks) unaffected | PASS (679/679) |

## 2. F-bar doc audit

One row per installable/fireable unit from the merged SG-01..04 surface. "Usage doc" follows
the SG-03-established convention: a co-located README/MANUAL, OR a self-documenting header
comment + `--help` (accepted for `board.sh`/`orchestrate.sh`-shaped entries), OR the README's
own Hooks/Commands table row (accepted for the 21 hooks and 27 commands, which have never had
one-file-per-hook docs and are not being retrofitted here, out of scope per the goal's "Not: a
marketing rewrite... per-internal-helper manuals" line).

### A. Spine (always wired, 6 hooks)

| Hook | Usage doc | Firing point |
|---|---|---|
| safety-gate | README Hooks table | PreToolUse(Bash), always on |
| ship-gate | README Hooks table + `docs/verification/README.md` (proof-gate contract) | PreToolUse(Bash), always on |
| spec-drift-guard | README Hooks table | PreToolUse(Write), always on |
| secrets-guard | README Hooks table | PreToolUse(Read\|Edit\|Bash), always on |
| commit-format | README Hooks table | PreToolUse(Bash), always on |
| anti-rationalization | README Hooks table | Stop, always on |

### B. Optional modules (install.sh `--with`, 9 names + 1 reserved)

| Module | Usage doc | Firing point |
|---|---|---|
| board | README Hooks table (`backlog-stage`) + `lib/board/board.sh` header (self-doc) + `docs/verification/{board-tool,board-mirror,board-writeback}/` | SessionEnd hook + `board.sh` CLI |
| session | README Hooks table (7 rows: context-readiness, output-offload, pre-compact-backup, post-compact-reinject, session-state-save, harvest, citation-guard) + README Install-module table (net-new, this PR) | various hook events, always-on once opted in |
| advisor | README Hooks table (`context-hints`) + README Install-module table | UserPromptSubmit |
| cosmetic | README Hooks table (6 rows) + README Install-module table | various (PostToolUse/Notification/StatusLine/SessionStart) |
| queue | `lib/queue/orchestrate.sh` + `lib/queue/queue.sh` headers (self-doc) + `docs/verification/{orchestrate,queue-launcher}.md` | `/kit:mega`, `/kit:dispatch`, the overnight queue launcher |
| stats | `lib/stats/README.md` (comprehensive) + `lib/stats/tool.toml` | `stats` CLI, reviewed at `/kit:retro` |
| quiz_gate | `commands/quiz-gate.md` (self-doc command prompt) + `docs/verification/quiz-gate.md` | `/kit:quiz-gate`, ADR-0031 §2/3 merge-boundary nudge |
| weekend_batch | `lib/queue/weekend-batch.sh` header (self-doc) + `docs/verification/weekend-batch.md` + ADR-0031 §3 | consumer-invoked directly (e.g. a consumer's own weekend-debt-paydown skill calls `weekend-batch.sh collect`/`mark-paid`); documented entry, no kit-side command wraps it |
| bridge | `lib/board/board.sh` header (extensive, mirror/status/writeback sections) + `docs/verification/{board-mirror,board-writeback}/` | `board.sh mirror\|status\|writeback`, opt-in per-repo via a `bridge=on` `boards.txt` row |
| team_mode | `install.sh`'s own reserved-module error message + PHILOSOPHY.md "Team mode: parked, not absent" + DECISIONS.md Decision C | N/A: not installable by design; the "gap" is that nothing installs, which is the intended state |

### C. Standalone subsystem commands (7, SG-03)

| Entry | Usage doc | Firing point |
|---|---|---|
| `board.sh` | own header + `--help` (pre-existing, SG-01/02 shape) | terminal entry, `/kit:*` commands that shell to it |
| `stats` CLI | `lib/stats/README.md` + `--help` (uv-installed typer app) | terminal entry, `/kit:retro` |
| `gate.sh` | own header + `--help` (SG-03) | terminal entry, wraps ship-gate/dispatch-gate/proof-gate/quiz-gate/etc. |
| `classify.sh` | own header + `--help` (SG-03) | terminal entry, `/kit:start`, `/kit:assign` |
| `spec.sh` | own header + `--help` (SG-03) | terminal entry, `/kit:spec` |
| `goal.sh` | own header + `--help` (SG-03) | terminal entry, `/kit:dispatch`, `/kit:mega` |
| `session.sh` | own header + `--help` (SG-03) | terminal entry, wraps `cc-observe`/`cc-recall`/`cc-intel` |

This category was already audited and justified in SG-03's own proof (`docs/proof/kitmod-subsystem-commands.md` §"F-bar per entry"): the header comment IS the doc, matching the pre-existing `board.sh`/`orchestrate.sh` convention. Re-confirmed here, no regression.

### D. Standalone orphans (bare `lib/` root scripts + orphan module dirs, 6)

| Entry | Usage doc | Firing point |
|---|---|---|
| `adopt.sh` | `commands/adopt.md` (self-doc command prompt) | `/kit:adopt` |
| `explain.sh` | `commands/explain.md` | `/kit:explain` |
| `pitch.sh` | `commands/pitch.md` | `/kit:pitch` |
| `precedent.sh` | own header (self-doc) + referenced directly in `commands/assign.md:109` and `commands/grill.md:65,69` | invoked from `/kit:assign` and `/kit:grill`, no dedicated command (by design, SPEC-068) |
| `skill-curator/` | `README.md` + `MANUAL.md` + `RUNBOOK.md` + `SPEC.md` (comprehensive) | `skills/skill-review/` skill, `bin/cc-improve` |
| `plugin-check/` | `README.md` (comprehensive: contract, install, use, troubleshooting) | standalone binary (`bin/plugin-check`), human/CI-run, documented entry per its own README |

### E. Substrate (1, SG-02 flagged this for a decision)

| Entry | Usage doc | Decision |
|---|---|---|
| `lib/ledger/ledger.sh` | header comment only (13 lines, 3 verbs: append/read/root) + one row in `lib/README.md`'s subsystem table | **Justified as sufficient, no new file written.** Same convention already accepted for `board.sh`/`gate.sh`/`orchestrate.sh` (header-as-doc); this substrate is smaller than any of those (67 lines total, 3 verbs) and has no independent user-facing surface, every call goes through `gate-ledger.sh`/`proof-ledger.sh`, which already document their own use. A standalone README here would restate the header verbatim. Revisit only if `ledger.sh` grows a fourth verb or a direct external consumer. |

## 3. Findings (non-blocking, named honestly rather than fixed)

- **`session` naming collision.** The install module named `session` (7 hooks: context-readiness, output-offload, ...) and the `lib/session/` subsystem (the `cc-observe`/`cc-recall`/`cc-intel` tools + `session.sh` dispatcher) share a name but are unrelated surfaces, no hook in the `session` module lives under `lib/session/`. This PR documents both clearly in their own tables (README's Hooks table for the module, `lib/session/session.sh`'s own header for the subsystem) so a reader is not misled, but does not rename either (out of scope: code changes belong to SG-01..04/07, not a docs sub-goal).
- **`advisor` naming collision.** The install module `advisor` (the `context-hints.sh` hook) and the `kit:advisor` AGENT (the cross-cutting review lens dispatched at the final review boundary) share a name and are also unrelated. Same treatment: documented distinctly, not renamed.
- Both collisions predate this sub-goal (SG-04 named the install modules; the `session`/`advisor` subsystem and agent names predate kit-modularity entirely) and are surfaced here so a future sub-goal can decide whether to rename, not silently inherited.

## 4. NC: delete-a-module's-doc -> audit flags the gap

Built a minimal audit checker (module -> expected doc path(s), exits 1 with a `[GAP]` line if
none of the paths exist) to demonstrate the audit table above is not just prose, it is a
checkable claim.

```
$ bash lib/stats/README.md exists? -> yes
$ mv lib/stats/README.md /tmp/kitmod06-stats-readme.bak
$ ./audit-check.sh
[GAP]  stats -> NONE of: lib/stats/README.md
[ok]   board -> lib/board/board.sh
[ok]   gate -> lib/gate/gate.sh
[ok]   ledger -> lib/ledger/ledger.sh
exit=1

$ mv /tmp/kitmod06-stats-readme.bak lib/stats/README.md
$ ./audit-check.sh
[ok]   stats -> lib/stats/README.md
[ok]   board -> lib/board/board.sh
[ok]   gate -> lib/gate/gate.sh
[ok]   ledger -> lib/ledger/ledger.sh
exit=0
```

Verdict: PASS. Deleting `stats`'s usage doc flips its row from `[ok]` to `[GAP]` and the
checker's exit code from 0 to 1; restoring it flips both back. `git status --short` after
restore showed only this PR's real edits (`README.md`, `docs/PHILOSOPHY.md`), confirming the
restore was clean.

## 5. `ledger-observatory` re-grep (SG-02 handoff)

```
$ grep -rIn "ledger-observatory" --include="*.py" --include="*.sh" --include="README.md" .
./tests/test-advisor-ledger-emit.sh:10:   (comment, describes the historical parse the move made obsolete)
./lib/stats/tests/test-mega-durations.sh:3:   (comment, historical framing of an ask)
./lib/stats/tests/test-docs-wiring.sh:64-67: (checks ops-toolkit's OWN MANIFEST.md still carries
                                              a historical row about the OTHER repo's tool; not
                                              a live label in THIS repo)
./lib/stats/tests/lib/conform.sh:3:           (comment, points at the pre-move doc path)
./lib/stats/README.md:15,17:                  ("History." section, explicitly retrospective)
```

All 6 hits are either comments describing the past migration or a check on another repo's
still-legitimate historical record; none is a live read-side identifier the SG-02 rename
missed. The one instance the SG-02 conductor caught and swept (`anomalies.py:689`) does not
reappear. Verdict: PASS, no stray live labels.

## 6. Confirmation run-table

| Check | Command | Result |
|---|---|---|
| Structural suite | `bash tests/test-meta.sh` | 679/679 PASS |
| NC delete-doc | see §4 | GAP flagged then restored, exit 1 -> 0 |
| Re-grep | see §5 | 0 live-label hits |
| Doc-diff | `git diff --stat README.md docs/PHILOSOPHY.md` | 2 files changed, additive only (no deletions besides moved text) |

## 7. Reproduce

```bash
cd dwarves-kit
bash tests/test-meta.sh 2>&1 | tail -5

# NC
mv lib/stats/README.md /tmp/stats-readme.bak
test -e lib/stats/README.md && echo ok || echo GAP
mv /tmp/stats-readme.bak lib/stats/README.md

# re-grep
grep -rIn "ledger-observatory" --include="*.py" --include="*.sh" --include="README.md" .
```
