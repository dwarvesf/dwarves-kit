# Sub-goal 07: retire-sweep (ops-toolkit, HELD final PR)

**Merge policy:** auto (but this is the FINAL PR under gated-final , OPEN it, do not merge; held for Han's single click)
**Time budget:** 1-2 hours of loop work
**Proof:** run-table , a grep sweep proving no removed tool asserts itself as live/canonical going forward; each moved code dir is `git rm`'d down to a `MOVED.md` tombstone + MANIFEST row; `git log tools/<name>/` still resolves history post-remove; `redeploy.sh` no longer references the 4 now-kit-wired hooks. Rung 2 (docs/metadata + file-removal change; uses the ship-gate `proof-ledger.sh override` escape hatch for the non-behavioral parts, same precedent as runner-fastpath 03R/05R).
**Design:** obvious (metadata + banner + MANIFEST + a redeploy.sh strip; the retire convention is fixed by 03R/05R precedent)
**Depends on:** 01, 02, 03, 04, 05, 06 ALL merged (retire only once the kit copies exist)
Model: sonnet
**Branch:** chore/kit-foldin-07-retire-sweep
**PR base:** main

## Outcome

The ops-toolkit side is a clean HARD-REMOVE of everything that moved into the kit, in ONE sweep (not a PR per tool). Han's directive 2026-07-05: don't leave code stubs behind (a `status=moved` stub still "sits in the old place"). Rationale check that makes this safe: `git log --follow` does NOT span repos anyway (a cross-repo move is delete+add, not a rename , follow never crosses the repo boundary), so ops-toolkit's own git history preserves each tool's full past whether or not the working tree keeps a stub. So for each CONFIRMED-moved tool (`cc-backlog`, `cc-citation-guard`, `cc-context-hooks`, `cc-harvest`, `cc-observe`, `cc-recall`, `cc-intel`, `cc-self-improve`, `cc-plugin-check`, `verify-claim`): `git rm -r` the tool's code directory, leaving ONLY a lightweight **tombstone** , a 3-line `tools/<name>/MOVED.md` (what it was + the kit path + the merge SHA) + the MANIFEST.md row set to `moved`. `tools/meta-agent` (dup of `kit:meta-agent`) and `cc-workflows` (dropped, 10 LOC) get the same tombstone treatment (`abandoned`, pointing at the kit agent / noting the drop). **Also fold in the cleanup Han flagged:** the already-moved `tools/ledger-observatory` + `tools/mega-runner` are currently retire-STUBS from runner-fastpath (03R/05R) , hard-remove those code dirs too (their kit copies are merged + tested), same tombstone. `redeploy.sh` is stripped of the 4 hooks now wired by the kit installer. `cc-money-gate` is UNTOUCHED (stays ops). Nothing is truly lost , git history + the tombstone pointer preserve everything; the working tree just stops carrying dead code.

## Quality bar

A clean, boring hard-remove. Anyone reading an old tool's dir finds only a `MOVED.md` tombstone pointing at the kit path. No dangling live-pointer anywhere claims a moved tool is still the canonical home. `redeploy.sh` no longer tries to snapshot-deploy hooks the kit installer now owns , but still deploys whatever legitimately stays ops-toolkit-side.

## How to close the loop

- Confirm all of 01-06 merged (read the ROADMAP boxes + `gh pr view` each). ALSO confirm the already-moved `ledger-observatory` + `mega-runner` kit copies are merged (they are , runner-fastpath).
- For each moved tool: `git rm -r tools/<name>/`, then write a 3-line `tools/<name>/MOVED.md` tombstone (what it was + kit path + merge SHA) and set the MANIFEST.md row to `moved`/`abandoned`. (Yes, the dir keeps ONLY `MOVED.md`.)
- Same hard-remove+tombstone for `tools/meta-agent` (-> `kit:meta-agent`), `tools/cc-workflows` (dropped), AND `tools/ledger-observatory` + `tools/mega-runner` (the runner-fastpath retire-stubs Han wants gone).
- Strip `redeploy.sh`: remove the 4 hooks (backlog/citation-guard/context-hooks/harvest) from its snapshot+symlink+settings-wire logic; keep everything else. Verify it still runs for the remaining tools.
- Grep sweep: `grep -rniE 'cc-(backlog|citation-guard|context-hooks|harvest|observe|recall|intel|self-improve|plugin-check)|tools/(verify-claim|meta-agent|ledger-observatory|mega-runner)' --include='*.md' --include='*.toml' --include='*.sh'` across ops-toolkit; for each hit, confirm it is historical (a completed mega RUN_REPORT, a dated log , leave alone) OR update it if it asserts the old path as live/canonical. Note any ambiguous one (like runner-fastpath 05R did with plannotator-gate).
- `git log tools/<removed>/` still shows full history post-`rm` (git keeps deleted-file history); spot-check 2-3.

Kit-adopted repo (ops-toolkit): record the gates via `bash lib/gate-ledger.sh`; for the non-behavioral metadata parts, the audited `proof-ledger.sh override` is the correct escape hatch (03R/05R precedent), NOT hitting the gate cold.

**Done =** every moved tool's code dir is `git rm`'d down to a `MOVED.md` tombstone + `moved`/`abandoned` MANIFEST row (incl. the already-moved ledger-observatory + mega-runner), `redeploy.sh` no longer references the 4 kit-wired hooks (and still runs), the grep sweep shows no stale live-pointer, `git log` still resolves history for the removed dirs, all captured in `docs/verification/kit-foldin-retire-sweep.md`. THEN OPEN the PR and STOP , this is the held final PR.

## Handoff on completion

1. Flip box, record PR # (but do NOT merge , held for Han).
2. HANDOFF.md: mega BUILD-COMPLETE, final PR #<N> held for Han; convergence gate (install-into-temp-HOME + green suites + dangling-ref grep) is the close.
3. DECISIONS.md: record any ambiguous grep-hit judgment calls.
4. Append the ops-toolkit `_meta/LAB_LOG.md` mega-arc entry (SPEC-005 close-out) on THIS branch so it rides into the final PR.
5. Report in records, EXIT (emit the gate-pause approval banner).

## Scope edges

**In:** `git rm` of every moved tool's code dir + a `MOVED.md` tombstone each, `MANIFEST.md` rows, `redeploy.sh` (strip the 4 hooks), the already-moved ledger-observatory + mega-runner stubs, `_meta/LAB_LOG.md` (the close-out line).
**Out:** dwarves-kit (all kit landings are SG-01..06); `cc-money-gate` (stays); `cc-worktree-provision` + `review-findings-memory` (deferred).
**Not:** removing a tool whose kit copy is NOT confirmed-merged (safety: confirm each first); editing historical RUN_REPORTs/logs; touching cc-money-gate; deleting git HISTORY (only the working-tree code , history stays); changing MANIFEST columns (Status cell only).

## Where to look

`ops-toolkit/tools/cc-*/tool.toml` + READMEs, `MANIFEST.md`, `tools/redeploy.sh`, runner-fastpath's 03R/05R goal files + their merged PRs (#709/#710) for the exact retire shape, memory `megagoal-lifecycle-rule`.

## PR body

Hard-remove the ops-toolkit copies of every cc-* tool moved into the kit (`git rm` -> `MOVED.md` tombstone + `moved` MANIFEST row), same for meta-agent (dup) + cc-workflows (dropped) + the already-moved ledger-observatory + mega-runner stubs, strip `redeploy.sh` of the 4 now-kit-wired hooks. Git history preserved (removal, not history-rewrite); `cc-money-gate` stays.

Verify: grep sweep (no stale live-pointer), MANIFEST rows, redeploy.sh still runs, `git log` resolves the removed dirs. Proof: `docs/verification/kit-foldin-retire-sweep.md`. HELD final PR , depends on kit PRs #<01..06>.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-foldin/ROADMAP.md`.

## Notes
