# Proof of done: research-output-paths (bug lane, no spec)

Bug fix: research docs, the decision brief, and CONTEXT.md were written to fixed
filenames (`docs/research/{stack,features,architecture,pitfalls}.md`,
`docs/briefs/DECISION-BRIEF.md`, `docs/briefs/CONTEXT.md`). Consumer repos commit and
merge these files, so a second feature run overwrites the first feature's docs once both
branches land on main (observed in ops-toolkit: two lost decision briefs and a pitfalls
report, plus a worker reading an overwritten `features.md` that belonged to a different
feature). Every writer (research-{stack,context,architecture,pitfalls} agents,
`spec.md`, `think.md`, `design.md`, `ui-design.md`) now derives `<date>`/`<slug>` and
writes to a slugged filename; every reader (`brief-reviewer`, `code-reviewer`,
`execute.md`, `next.md`, `assign.md`, `devs-team.md`, `visual-team.md`,
`review-team.md`) resolves the slugged file first and falls back to the legacy fixed
name so an in-flight worktree still works.

## Green run

Command: `bash tests/test-research-arch-contract.sh`
Exit: 0
Output (tail): `Passed: 28 / 28`

Command: `bash tests/test-research-pair-contract.sh`
Exit: 0
Output (tail): `Passed: 41 / 41`

Command: `bash tests/test-meta.sh` (repo-wide structural integrity: manifests,
frontmatter, cross-links)
Exit: 0
Output (tail): `Passed: 843 / 843`

## NEGATIVE CONTROL

Run live via `bash lib/gate/negctl.sh <root> "<test-cmd>" "<mutate-cmd>"` against the
committed tree:

```
Command: bash tests/test-research-arch-contract.sh && bash tests/test-research-pair-contract.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' 's/docs\/research\/<date>-<slug>-architecture\.md/docs\/research\/architecture.md/g' agents/research-architecture.md commands/spec.md
Changed: agents/research-architecture.md, commands/spec.md
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- agents/research-architecture.md commands/spec.md
Exit: 0 (green after restore)
Verdict: PASS
```

## Reproduce

```bash
cd dwarves-kit
bash tests/test-research-arch-contract.sh
bash tests/test-research-pair-contract.sh
bash tests/test-meta.sh
```

## Scope note

Headless, no visible surface: these are prompt/instruction markdown files consumed by an
LLM at command-dispatch time, not a rendered UI; the text-pin contract tests above are the
proof form for this change (same shape SPEC-210/211 already established for these files).

VERDICT: PASS
