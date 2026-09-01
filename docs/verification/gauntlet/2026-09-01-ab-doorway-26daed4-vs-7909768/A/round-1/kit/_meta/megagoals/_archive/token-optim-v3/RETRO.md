# Retro , token-optim-v3 wave (2026-07-01)

Reflection on shipping the remaining sub-goals + the mid-review scope expansion + the bottom-up merge.
Honest, evidence-first: every claim below traces to something that actually happened this session.

## What shipped

| | |
|---|---|
| Sub-goals | 7 (SG-01..07), all merged |
| End-review PRs | 6 across 3 repos (dwarves-kit #90/#91/#92, dotfiles #167, ops-toolkit #608) + gate-contract dotfiles #171 + archive #609 |
| Review | 2 adversarial rounds, 5 lens-passes (3 + 2) + per-finding fact-checks |
| Test growth | routing 10→14, v3-arms 9→18, meta-agent 38→65, +role-classify 15; kit guards held 508/508 throughout |
| Merge | bottom-up; 1 real stacked-PR conflict resolved by hand |
| Scope added mid-review (Han) | default-install → Mode C same-run synthesis → open-ended roles → shared `role-classify` → SPEC-089 → mega-goal↔kit audit → G1/G2 |

## What worked

- **Two review rounds, and the second reviewed the FIXES.** Round 2 caught a regression that round 1's own fixes introduced (the `/dcompact` `mktemp` paths stored in shell vars that don't survive across Bash-tool calls). Self-review would never have found it; reviewing the fix commits, not just the original code, is the reason it was caught before merge.
- **Fact-checking verdict-driving findings before acting.** Round 1's one HIGH ("orchestrate.sh skip-permissions surface") was a phantom , a stale local `master` ref made the three-dot diff surface already-merged work. `gh pr diff 91` proved the PR touched only 10 files. Refuted, not fixed. A fresh-context reviewer hallucinated scope; verifying killed it in one cycle instead of a wasted fix.
- **The kit's own anti-drift guards enforced completeness.** `test-meta.sh` fails closed if a new agent lands without its MANUAL/architecture/README rows , so "add a meta-agent" mechanically forced the roster sync. Structure did the remembering.
- **A sharp question produced a real design correction.** Han's "8 fixed domains won't scale to technical-doc-writer / typescript-dev" flipped the design from a closed classifier to open-ended (classifier = cheap fast-path hint, LLM = the unbounded authority). Better architecture from one critique.
- **Proofs were captured evidence, not assertions** , run-tables, negative controls (infinite-cost guard, failing-arm exclusion), 508/508 , which is what let the merge be a confirmation, not a leap.

## What hurt (with root cause)

- **Stale local `master`/`main` ref was the single biggest pain, and it bit twice.** (1) It manufactured the phantom HIGH finding above. (2) It caused the real `#91 → #92` merge conflict: #92 was branched from #91's *original* tip, #91 then evolved heavily, both touched `meta-agent.md`. Root cause: not fetching/rebasing onto the freshest base before diffing-for-review and before stacking.
- **My own fixes introduced a regression.** I fixed a security finding (static `/tmp` → `mktemp`) without thinking through the slash-command execution model (shell vars don't persist across separate Bash calls), breaking steps 3-4. Fixes got less rigor than original code until round 2 forced it.
- **First-pass tests passed for the wrong reason.** The tie-break test was a tautology (`T1==T2` always holds regardless of the fix); the missing-prior test never pinned the `2>/dev/null` guard. Round 2's test-validity lens caught both. Writing a test is not the same as writing a test that fails on regression.
- **PR #91 accreted scope under interactive iteration** , from "SG-05 meta-agent drafter" to a whole dynamic-synthesis system. Flagged twice; Han chose to keep it one PR. Not wrong, but a held PR under live back-and-forth grows silently.
- **Cross-repo/worktree friction.** Edits landed in the wrong checkout twice (`execute.md` to the main checkout instead of the worktree); recurring bash-in-zsh gotchas (`set -- $spec` GraphQL errors, `noclobber` needing `>|`, an `index.lock` race that silently skipped a commit).

## Action items (carry forward)

1. **`git fetch origin <base>` before review-diffing and before stacking a PR.** The stale ref caused both the phantom finding and the merge conflict , the highest-leverage fix here.
2. **Always run a second adversarial pass on the FIX commits**, not just the original diff. Round 2 earned its keep.
3. **Fact-check any CRITICAL/HIGH finding against the live tree** (`gh pr diff` / grep) before spending a fix cycle on it.
4. **A test must fail on regression**: assert the contract, add a negative control, mentally revert-and-check before trusting a green.
5. **When a held PR accretes scope across iterations, decide split-vs-keep consciously** at each addition, not at the end.
6. **Verify cwd/target when editing across worktrees** (the execute.md-to-wrong-checkout slip).

## Durable lessons worth capturing to memory

- Stale base ref causes BOTH phantom review findings and stacked-merge conflicts , fetch the base first. (cross-project)
- Review the fixes, not just the original code , a second pass on fix commits catches self-inflicted regressions.
- A fresh-context reviewer can hallucinate scope from a stale-base diff , fact-check verdict-driving findings before acting.
