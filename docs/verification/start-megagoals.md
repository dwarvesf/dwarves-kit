# Proof of done: start-megagoals
Profile: feature   Proof class: behavioral

## 1. Acceptance criteria

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | `lib/goal/megagoals.sh list` finds every `ROADMAP.md` under the four known mega-goal shapes | PASS | R1 |
| 2 | Sub-goal done/total is counted from the `## Sub-goals` section's `- [x]`/`- [ ]` tokens, both the plain checklist shape and the table-Status-cell shape, and never from a checkbox outside that section | PASS | R1 |
| 3 | A fully-done mega-goal (done == total > 0) is hidden by default, shown with `--all` | PASS | R1 |
| 4 | `HANDOFF:<yes|no>` and `POINTER:<path or ->` read `HANDOFF.md` / `POINTER_PROMPT.md` in the mega-goal folder | PASS | R1 |
| 5 | Output is capped at `--limit` (default 5), extras collapse to one `+N more` line, the trailing count line stays uncapped | PASS | R1 |
| 6 | `handoffs.sh list` gains the same `--limit` cap (default 5), existing output shape (liveness tags, excerpt, count line) unchanged | PASS | R1 |
| 7 | `commands/start.md`'s `2c. Pick up` block caps every list at 5 + `+N more`, adds a Mega-goals bucket, and the recommended-next-action order becomes LIVE handoff -> mega-goal POINTER_PROMPT -> goal draft -> top queued row | PASS | R2 (inert, docs) |
| 8 | Negative control: reverting the cap logic in either script turns its suite red | PASS | R3, R4 |
| 9 | `find_roadmaps` prunes `.claude/worktrees`, `node_modules`, `.git` so a repo with worktrees is not double-counted per checkout | PASS | R6, R8 |
| 10 | `count_subgoals` also tallies a `## Status` section (real ROADMAP shape used by ops-toolkit `herdr-quicklook/megagoals/*`), summed with `## Sub-goals`, without double-counting when one section is a checkbox-free table | PASS | R7, R9 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | `lib/goal/megagoals.sh` (new): `find_roadmaps`, `count_subgoals`, `cmd_list`. `lib/session/handoffs.sh`: `cmd_list` gains `--limit` (default 5) over the already-sorted rows. `commands/start.md`: `2c. Pick up` block gains per-bucket caps, a Mega-goals bucket, and the updated next-action order. |
| Where | `lib/goal/megagoals.sh`, `lib/goal/tests/test-megagoals.sh`, `lib/session/handoffs.sh`, `lib/session/tests/test-handoffs.sh`, `commands/start.md` |
| How it runs | `bash lib/goal/megagoals.sh list [--repo DIR] [--limit N] [--all]`, `bash lib/session/handoffs.sh list [--repo DIR] [--days N] [--limit N]`, both called from `/kit:start --full`'s `2c. Pick up` block. Both are read-only, zero network calls beyond the pre-existing `git fetch origin` `handoffs.sh` already did for board liveness. |
| Reversibility | Read-only tools; `git revert` on the three commits fully restores prior behavior. No state, no migration. |

## 3. Confirmation (runs)

| Run | When (ISO+tz) | Command | Exit | Verdict |
|---|---|---|---|---|
| R1 | 2026-09-18T09:05+07:00 | `bash lib/goal/tests/test-megagoals.sh` (and `/bin/bash`) | 0 | PASS (12/12 both shells) |
| R1b | 2026-09-18T09:06+07:00 | `bash lib/session/tests/test-handoffs.sh` (and `/bin/bash`) | 0 | PASS (17/17 both shells) |
| R2 | 2026-09-18T09:20+07:00 | `bash tests/run-all.sh --changed` | 0 | PASS (docs-only `commands/start.md` diff has no executable check of its own, inert; same shape as start-pickup.md's R2) |
| R3 | 2026-09-18T09:10+07:00 | `bash lib/gate/negctl.sh "$(pwd)" "bash lib/goal/tests/test-megagoals.sh" "sed -i '' 's/\[ \"\$limit\" -gt 0 \] && \[ \"\$total_n\" -gt \"\$limit\" \]/false/' lib/goal/megagoals.sh"` | 0 | PASS (green -> RED under mutation -> restored green) |
| R4 | 2026-09-18T09:12+07:00 | `bash lib/gate/negctl.sh "$(pwd)" "bash lib/session/tests/test-handoffs.sh" "sed -i '' 's/\[ \"\$limit\" -gt 0 \] && \[ \"\$total_n\" -gt \"\$limit\" \]/false/' lib/session/handoffs.sh"` | 0 | PASS (green -> RED under mutation -> restored green) |
| R5 | 2026-09-18T09:15+07:00 | `bash lib/goal/megagoals.sh list --repo /path/to/ops-toolkit --all --limit 30` (real repo, read-only) | 0 | 354 mega-goals total; sample row `mochi-icy-simplify  9/13  HANDOFF:yes  POINTER:_meta/megagoals/mochi-icy-simplify/POINTER_PROMPT.md` matches the folder's real ROADMAP.md checklist state |
| R6 | 2026-09-18T16:05+07:00 | `bash lib/goal/tests/test-megagoals.sh` (worktree-prune fixture, and Status-section fixtures, both shells) | 0 | PASS (15/15 both `bash` and `/bin/bash`) |
| R7 | 2026-09-18T16:10+07:00 | `bash lib/goal/megagoals.sh list --repo /path/to/ops-toolkit --all --limit 1000` (real repo, read-only, BEFORE fix vs AFTER fix) | 0 | BEFORE (origin/master, unpruned): 610 lines. AFTER (this fix): 52 lines, `51 mega-goals`; `quicklook-v03` goes from `0/0` (missed, no `## Sub-goals` header) to `11/11` (matches its `## Status` checklist by hand count) |
| R8 | 2026-09-18T16:12+07:00 | negctl: mutate the `.claude/worktrees` prune path to `__disabled__` | 0 | PASS (green -> RED under mutation -> restored green) |
| R9 | 2026-09-18T16:13+07:00 | negctl: mutate the `## Status` section-start match to `__disabled__` | 0 | PASS (green -> RED under mutation -> restored green) |

## 4. Run detail

### R1 GREEN
Command: `bash lib/goal/tests/test-megagoals.sh`
Exit: 0
Output (excerpt):
```
[1] open-list shown with correct done/total, excluding the Imported history checkbox
  ok: open-list line: open-list  1/2  HANDOFF:yes  POINTER:_meta/megagoals/open-list/POINTER_PROMPT.md
[3] open-table counted from the table's Status cell, 1/3
  ok: open-table line: open-table  1/3  HANDOFF:no  POINTER:-
[7] cap: 7 open mega-goals collapse to 5 lines + '+2 more'
  ok: 5 shown
  ok: collapse + count tail correct
[9] the other three mega-goal shapes are all discovered
  ok: experiments/, tools/*/docs/, docs/ shapes all found
smoke: all 12 passed
```
Verdict: PASS

### R1b GREEN
Command: `bash lib/session/tests/test-handoffs.sh`
Exit: 0
Output (excerpt):
```
[14] cap: 7 handoffs collapse to 5 lines + '+2 more', count line stays uncapped
  ok: 5 shown
  ok: collapse + uncapped count tail correct
[15] --limit overrides the default
  ok: --limit 2: 2 shown, +5 more
smoke: all 17 passed
```
Verdict: PASS

### R2 GREEN (repo-wide changed-suite gate)
Command: `bash tests/run-all.sh --changed`
Exit: 0
Verdict: PASS (see the run's own summary line for the suite count)

### R3 / R4 NEGATIVE CONTROLS
See the table above; both mutated the cap `if` guard to `false`, both went RED, both restored GREEN via `git checkout HEAD --`.

### R5 real-repo sample (read-only)
Command: `bash lib/goal/megagoals.sh list --repo /path/to/ops-toolkit --limit 5`
```
agent-method  0/3  HANDOFF:no  POINTER:_meta/megagoals/agent-method/POINTER_PROMPT.md
airwallex-xero-bank-rec  4/5  HANDOFF:no  POINTER:_meta/megagoals/airwallex-xero-bank-rec/POINTER_PROMPT.md
cf-quota-tracker  0/6  HANDOFF:no  POINTER:_meta/megagoals/cf-quota-tracker/POINTER_PROMPT.md
dictate-overlay  0/7  HANDOFF:no  POINTER:_meta/megagoals/dictate-overlay/POINTER_PROMPT.md
icy-mint-burn  4/9  HANDOFF:no  POINTER:_meta/megagoals/icy-mint-burn/POINTER_PROMPT.md
+157 more
```
Verdict: matches the real repo's ROADMAP.md files by inspection (spot-checked `mochi-icy-simplify` against its own `## Sub-goals` checklist: 9 `- [x]` of 13 total lines).

### ROLLBACK/RESTORE
`git checkout HEAD -- <file>` (run by negctl itself, confirmed green after). No deployed state to roll back; a plain `git revert` undoes all commits.

### R6-R9: worktree-prune + Status-section fix (2026-09-18)

Bug: `find_roadmaps` did not prune `.claude/worktrees`, so on a repo with git
worktrees every mega-goal was counted once per worktree checkout
(ops-toolkit: 610 printed lines, 558 of the 609 matching `ROADMAP.md` files
were under `.claude/worktrees/`). Fixed by pruning `.claude/worktrees`,
`node_modules`, `.git` in the `find`.

Separately, hand-verifying three real ops-toolkit ROADMAP.md files surfaced
a second real gap: `count_subgoals` only scanned `## Sub-goals`, but six
real mega-goal folders (`herdr-quicklook/megagoals/{quicklook-v03,
04-render-anything,05-pick-anywhere}`, `hermes-multiplex-followups`,
`icy-ops-skill-sync`, `icy-ops-duckdb`) track the authoritative tally under
a `## Status (source of truth; ...)` header instead of, or alongside, `##
Sub-goals`. Three of those (the `herdr-quicklook` ones) have no `##
Sub-goals` header at all and read `0/0` before the fix; `quicklook-v03` is
actually `11/11` (all sub-goals shipped) by hand count of its `## Status`
checklist. Fixed by also tallying `## Status`. Verified no real file has
live checkboxes in both sections at once (the `icy-ops-*` files pair a
real `## Sub-goals` checklist with an empty `## Status` template; the
`hermes-multiplex-followups` file pairs a checkbox-free `## Sub-goals`
table with the real `## Status` tally), so summing both sections does not
double-count; a fixture (`status-and-table`) pins this.

Corrected real ops-toolkit count: **51 mega-goals** (`--all --limit 1000`),
down from 610 printed lines pre-fix.

## 5. Reproduce

```
bash lib/goal/tests/test-megagoals.sh
bash lib/session/tests/test-handoffs.sh
bash tests/run-all.sh --changed
bash lib/gate/negctl.sh "$(pwd)" "bash lib/goal/tests/test-megagoals.sh" "sed -i '' 's/\[ \"\$limit\" -gt 0 \] && \[ \"\$total_n\" -gt \"\$limit\" \]/false/' lib/goal/megagoals.sh"
bash lib/gate/negctl.sh "$(pwd)" "bash lib/session/tests/test-handoffs.sh" "sed -i '' 's/\[ \"\$limit\" -gt 0 \] && \[ \"\$total_n\" -gt \"\$limit\" \]/false/' lib/session/handoffs.sh"
bash lib/gate/negctl.sh "$(pwd)" "bash lib/goal/tests/test-megagoals.sh" "sed -i '' \"s/-path '\*\/\.claude\/worktrees' -o/-path '__disabled__' -o/\" lib/goal/megagoals.sh"
bash lib/gate/negctl.sh "$(pwd)" "bash lib/goal/tests/test-megagoals.sh" "sed -i '' \"s/\/\^## Status\/    { insec=1; next }/\/__disabled__\/ { insec=1; next }/\" lib/goal/megagoals.sh"
```
