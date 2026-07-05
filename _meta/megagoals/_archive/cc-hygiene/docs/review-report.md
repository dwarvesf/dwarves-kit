# cc-hygiene final review round (sub-goal 09)

Fresh-context adversarial review over the MERGED set (sub-goals 01-05, 08 + scaffold),
plus the kit advisor in critique + over-suggest modes. Reviewers read the actual
merged commits across all three repos.

Merged set audited (all `gh pr view` = MERGED, no CHANGES_REQUESTED):
dotfiles #191 (01), #192 (03A); ops-toolkit #627 (02), #629 (03B), #631 (05),
#638 (08), #625 (scaffold); dwarves-kit #116 (04). Held gates: ops-toolkit #634 (06),
dotfiles #193 (07).

## Verdicts per lens

| lens | verdict | findings |
|---|---|---|
| security | HAS ISSUES | 1 MAJOR (override guard omits CI/IaC/build files), 1 Minor (rtk tmpdir) |
| architecture | 5/10 | 1 CRITICAL (deploy last-mile), 1 MEDIUM (CLAUDE.md budget contradiction), 2 MINOR |
| test-coverage | 7/10 | 1 HIGH (vacuous debounce test); all 5 tool proofs reproduced live, none fabricated |
| advisor (critique) | advisory | 2 HIGH (deploy last-mile; per-PR bookkeeping deferred), 1 MEDIUM (PR#191 bundling), 1 LOW |
| advisor (over-suggest) | 8 proposals | filed to NOTES ## Proposed additions |

## CRITICAL / MAJOR / HIGH , resolution

| # | sev | finding | resolution |
|---|---|---|---|
| 1 | MAJOR (sec) | proof-ledger override source-guard omitted `.yml/.yaml` (CI), `.tf/.tfvars` (IaC), Makefile/Dockerfile/Justfile , same bypass class as rtk-611 | **FIXED** dwarves-kit PR #118: added those to source detection + 4 tests (CI-yaml/.tf/Makefile REJECTED, plain config PASS control) |
| 2 | HIGH (test) | session-state debounce test keyed only off the DEBUG log string; a keep-echo/drop-exit-0 mutation passed it | **FIXED** dwarves-kit PR #118: archive-count side-effect oracle; mutation-verified (mutation now fails the assertion) |
| 3 | CRITICAL (arch) + HIGH (advisor) | **deploy last-mile**: dotfiles local `main` diverged from origin (2 unpushed local commits + missing the merged #191/#192), and the dwarves-kit deployed copy (`~/.claude/dwarves-kit`) is not re-installed , so the merged fixes are NOT live on the machine (live `effortLevel:high`, hook still old, override guard not deployed) | **DEPLOY ACTION for Han** (below). NOT auto-reconciled: it touches Han's unpushed local commits + runtime; and it is naturally the act of merging the held gates. Documented, not code-fixable on this branch. |
| 4 | MEDIUM (arch) | CLAUDE.md Log-hygiene (one-line default) vs Session-close ("5-10 lines for routine PRs") contradiction; 02/03 fixed one side | **FIXED** this branch: CLAUDE.md Session-close budget aligned to one-line default |
| 5 | Minor (sec) | rtk selftest leaves a `mktemp -d` tmpdir | **FIXED** this branch: `trap 'rm -rf "$tmph"' EXIT` |
| 6 | HIGH (advisor) | ops-toolkit sub-goal PRs didn't touch LAB_LOG / close backlog rows | **BY DESIGN**: the mega-goal batches the LAB_LOG arc + BACKLOG closures into THIS 09 branch (contract), dogfooding 02's "no bookkeeping-only PR" rule. Done here. |
| 7 | MEDIUM (advisor) | PR #191 bundled an unrelated process-addition (invocation-template coverage-delta) | Known: the worktree-base-ref bug bundled Han's unpushed `072c6aa`; documented in NOTES. Content is Han's own; no revert. |

MINOR/LOW (rtk proof INDEX shape, global-CLAUDE hook-coverage doc, wrap-session heading line) filed to NOTES ## Proposed additions, not built (per 09 scope: only CRITICAL/MAJOR fixed).

## Required deploy action for Han (finding #3)

The merged code is correct on origin; it is not yet LIVE. When merging the held gates, also:
1. **dotfiles**: reconcile local `main` with `origin/main` (it has 2 unpushed commits `072c6aa`, `125b396` , `072c6aa`'s content is already on origin via #191, `125b396`/browser-harness-js is genuine unpushed work). Rebase/fast-forward, then `chezmoi apply` to ship 01 (effortLevel medium + policy blocks) + 03 (narrowed hook).
2. **dwarves-kit**: re-run the kit install so `~/.claude/dwarves-kit` picks up 04 + #118 (the override guard that gates pushes).

## Bottom line

The mega-goal's merged diffs are sound (per-artifact reviewers confirmed; all 08 tool
proofs reproduced live, none fabricated). Every CRITICAL/MAJOR/HIGH is fixed (#118 +
this branch) or is a deploy action for Han. The one systemic lesson: shipping to source
control != deploying to the runtime the changes govern.
