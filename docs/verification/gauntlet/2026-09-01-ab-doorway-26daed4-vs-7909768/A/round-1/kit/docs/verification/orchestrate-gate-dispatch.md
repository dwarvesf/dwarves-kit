# Proof of done: orchestrate.sh gate dispatch + merged-PR box reconciliation

Two defects observed on a real 5-sub-goal mega-goal run (foundation-workers
`_meta/megagoals/retire-apps/`, its `RUN_REPORT.md` "Incidents" holds the field record), plus one
decompose rule the same run needed.

## Acceptance criteria

| # | Criterion | Met |
|---|---|---|
| AC1 | A box flipped inside a sub-goal's now-merged PR counts: the driver reconciles against `origin/<default>` before the no-self-claim halt | yes (A1) |
| AC2 | No-self-claim is unchanged: a remote box counts only when its line carries a real `PR #<n>` | yes (A2, negative control) |
| AC3 | A dirty tree is never force-pulled; the remote copy is read for the check only | yes (A3, negative control) |
| AC4 | Outside a git repo the guardrail halt is byte-identical | yes (A4, negative control) |
| AC5 | A `gate` sub-goal is DISPATCHED, its prompt carries the held-PR contract, and the loop holds afterwards on its PR URL | yes (B1, B1b) |
| AC6 | A gate session that opened no PR halts the loop, exactly like an unflipped box | yes (B2, negative control) |
| AC7 | `MEGA_GATE_DISPATCH=0` restores the stop-before-running behavior | yes (B3, B6 negative control, plus the legacy blocks in the three existing orchestrate test files) |
| AC8 | `gate!` is dispatched too, then halts the whole loop, on the serial path and under a wave | yes (B4, B5) |
| AC9 | `--dry-run` names the dispatch-then-hold plan | yes (B6) |
| AC10 | `commands/mega.md` Step 1 carries the port-then-delete re-diff rule, mirrored into the never-diverge skill copy | yes (`commands/mega.md`, `dotfiles` PR) |

## What changed

`lib/queue/orchestrate.sh`:

- `_default_branch` / `_roadmap_remote_view` / `_sg_pr_url` (new helpers).
- The grounded-completion check consults `origin/<default>` before halting. Clean tree on the
  default branch: `git fetch` + `merge --ff-only`. Dirty tree: `git show origin/<default>:<path>`
  into a temp file, read-only, plus a locked `flip` of the one box line the remote already carries
  so `_next` cannot re-pick the same sub-goal forever.
- `MEGA_GATE_DISPATCH` (default 1): a `gate` / `gate!` sub-goal runs through the same dispatch body
  an `auto` one does. `_build_prompt` takes an optional policy argument that injects the held-PR
  contract (draft PR, `mega-merge.sh mark`, never merge, never flip the box). The hold happens after
  the session and is grounded on `_sg_pr_url`. `gate!` forces itself as the cycle's pick under a
  wave, so the wave still quiesces around it.
- `GH_CMD` mock seam for the PR lookup.

`commands/mega.md`: the port-then-delete re-diff rule in Step 1; the driver's gate-dispatch behavior
named in Step 5.

## Confirmation run-table

| Command | Exit | Result |
|---|---|---|
| `bash tests/test-orchestrate-gate-dispatch.sh` | 0 | 23/23 PASS (`ALL PASS`), 6 of them negative controls |
| `bash tests/test-orchestrate.sh` | 1 | 61 PASS; the 2 failures (`dry-run SG-02 inherit`, `SG-02 got an unexpected --model`) are PRE-EXISTING on `origin/master`, byte-identical to the baseline capture |
| `bash tests/test-orchestrate-hardening.sh` | 0 | 12/12 PASS |
| `bash tests/test-orchestrate-wavefront.sh` | 0 | 103/103 PASS |
| `bash tests/test-meta.sh` | 1 | 806/813; the 7 failures are PRE-EXISTING and the failure set is identical to the baseline capture (verified by set-diff) |

Verdict: PASS. Every new assertion is green; no test that passed before regressed.

## Negative controls (RED-by-design)

| Control | What it poisons | Observed |
|---|---|---|
| A2 | remote box flipped WITHOUT a `PR #<n>` | run halts nonzero, "did not check its ROADMAP box" |
| A3 | dirty working tree | HEAD unmoved, staged work intact, remote read for the check only |
| A4 | megagoal outside any git repo | halt message and exit code unchanged |
| B1b | the `auto` sub-goal's prompt | carries no `HELD SUB-GOAL` block |
| B2 | gate session opens no PR | run halts nonzero, "opened no PR" |
| B3 / B6 | `MEGA_GATE_DISPATCH=0` | gate sub-goal never dispatched; old stop message and plain `(gate)` plan label return |

## Reproduce

```bash
bash tests/test-orchestrate-gate-dispatch.sh
bash tests/test-orchestrate.sh
bash tests/test-orchestrate-hardening.sh
bash tests/test-orchestrate-wavefront.sh
bash tests/test-meta.sh
```

The A-block fixtures build a real bare remote plus a clone, and the mock session pushes the box flip
to the remote without touching the driver's checkout, so the merged-PR shape is reproduced for real
rather than simulated. The B-block fixtures mock `gh` through `GH_CMD`, so no network and no GitHub
auth are involved.
