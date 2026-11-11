# Decision brief: a team stamp for repos whose team does not run the kit

**Status:** DRAFT. Nothing is built. Three board rows cite this brief.
**Question:** one operator runs the kit. Their teammates do not, and the teammates' coding agents do most of the work. How does the repo carry the kit's discipline to agents that have no plugin?

## Verified current state

One private product repo was fitted by hand over two days, with three people on the team. The teammates' agents then followed the rules on their own: four pull requests arrived with a proof file, a board row and a tagged changelog line, and CI caught the one rule an agent missed. The operator's record of that work is a dated research note in their private toolkit (title "A kit-free agent harness for a team repo"). This brief holds the design that came out of it, so the rows below stand without the note.

What the hand fit showed about the kit as it is:

| Finding | Evidence | Row |
|---|---|---|
| The kit cannot generate this harness. Every piece was written by hand. | About twenty files: rules, two hooks, six scripts with tests, a CI job, templates. | team stamp |
| The adopt pointer puts kit-only rules at the top of `AGENTS.md`. A teammate's agent reads them as binding. | The pointer says "stop and ask a human before an architecture or interface change". The team rule asked for a second person only on a short list of irreversible changes. The clash stood for a day. | adopt pointer |
| The full lane fires on any hard-path file, whatever the size of the change. | Four small CI and config edits each owed twelve recorded phases. Most records were overrides. The repo turned the lane gate off. | lane gate sizing |

## Design

Enforcement moves from the plugin into the repo, in four layers. Each layer works with no kit on the machine.

```
 agent about to act
   │
   ├─ 1  AGENTS.md            read at session start        advice
   ├─ 2  project hook         blocks the wrong command     Claude Code only
   ├─ 3  CI job on each PR    fails the wrong PR           every agent, every person
   └─ 4  daily digest         shows what slipped through   the operator
```

A refusal at layer 2 or 3 names the rule in one line and the fix command in the next. That is what lets an agent correct itself with no human in the loop.

### What the stamp generates

One command, run by the operator in the target repo, writes these files. Each script arrives with its test.

| Piece | File | Rule it carries |
|---|---|---|
| Agent rules, self-contained | `AGENTS.md` | Commands map, playbooks, lessons, team rules. The kit marker stays on line 1. A short closing section says the kit is optional. |
| People's copy of the rules | `docs/TEAM-WORKFLOW.md` | The same rules with the why. A CI check fails a PR that changes one copy and not the other. |
| Command guard | `.claude/settings.json`, `scripts/agent-guard.sh` | Blocks a bare PR merge, a push to the default branch, a commit on the default branch. |
| Lessons at session start | `scripts/agent-lessons.sh`, `.claude/memory/MEMORY.md` | Prints the index of repo lessons. Seeded with the generic CI lessons. |
| Playbook | `.claude/skills/ship-pr/SKILL.md` | Issue to merged PR, with exact commands. Repo-specific playbooks stay hand-written. |
| PR shape check | `scripts/pr-shape.sh`, a CI job | Conventional title, a proof file for a behavior change, a board row or `Closes #n`, a tagged changelog line for product code, shell lint on changed scripts, rule parity. |
| Local check | `scripts/check.sh` | Runs the same checks before a push. |
| Owners | `OWNERS.md`, `scripts/check-owners.sh` | Every script, workflow and job has one owner: a person, or a named agent with a human sponsor. |
| Merge guard | `scripts/pr-merge.sh` | Waits for checks, refuses a draft, a red check or a conflict, and asks for a second person's approval on listed paths. |
| Negative control | `scripts/negctl.sh` | Green, break, red, restore, green, with a proof block ready to paste. |
| Work queue | an issue form, `scripts/issues-from-rows.sh`, a PR template | The board is the plan. Issues are the queue. A claim is an assignee. |
| Changelog by reader | tag list in `CHANGELOG.md`, `scripts/release-notes.sh` | Lines carry a component tag. Release notes drop the team-tooling lines. |
| Digest | `scripts/team-digest.sh` | Merged PRs, open PRs, open issues, decisions waiting. Replaces a stand-up. |
| Proof guide | `docs/verification/README.md` | How to write a proof, one file per PR. |
| Gate config | `.kit.toml` | Proof gate on, lane gate off. |

Left to the repo: language test jobs in CI, product playbooks, the list of irreversible paths, and who posts the digest.

### Rules for the generator

- The generated files are plain copies the repo owns. They must run with no kit installed. No file may point at a path under the kit.
- The stamp is idempotent and never overwrites a file the repo edited. It reports drift, as `adopt` does.
- A second run after a kit upgrade offers the diff per file. The operator picks.
- The hook contract and the skill format are read from the vendor docs at build time, not from memory.

## Build order

1. **Adopt pointer.** Smallest change, and it removes an active contradiction in every adopted repo. The pointer block keeps its line-1 marker and its four generic rules move under a heading that says they apply only when the repo states no rules of its own.
2. **Lane gate sizing.** The hard-path rule keeps the full lane for a change that alters what a gate or a hook does. A change that only adds a workflow file, flips one config key, or edits a comment sizes by its diff.
3. **Team stamp.** A new verb next to `adopt`. Start from the hand-fitted repo's files as the templates, strip the product names, and prove the stamp on a scratch repo with a clean-room agent that has no kit.

Rows 1 and 2 stand alone. Row 3 depends on row 1, because the stamp writes the same `AGENTS.md`.

## Conformance

- A team stamp is a generator, not a runtime. It adds no daemon and no service.
- It does not weaken a gate for a kit user. The operator's own session still runs the proof gate through `.kit.toml`.
- It binds Claude Code through the project hook, and every other agent through CI. A person who merges from the GitHub site passes everything on a plan without branch protection. The brief accepts that limit and says so in the generated rules.

## Exit criteria

- Adopt pointer: an agent in an adopted repo that states its own rules is never told to stop for a change those rules allow. Test: a fixture repo with its own rule section, checked by the adopt test suite.
- Lane gate sizing: a PR that adds one CI workflow file passes with a proof and no phase ledger. A PR that changes a hook's behavior still owes the full lane. Both pinned as classifier test rows.
- Team stamp: on a scratch repo, a clean-room agent with no kit opens a PR that passes the generated CI, and a bare merge command is blocked with the fix line. The gauntlet records the run.

## Related

- Parking-lot item "Team mode (attestation, not sync)" covers several engineers who all run the kit. This brief covers the opposite case: one kit user, teammates without it.
- "Portable adopt" (consumer files resolve the kit at read time) touches the same pointer file as build step 1.
