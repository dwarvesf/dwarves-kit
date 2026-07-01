# Proof of done , meta-agent drafter (token-optim-v3 SG-05)

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| 1 | Meta-agent drafts a lint-passing subagent `.md` from a description | met |
| 2 | Meta-agent drafts a template-conforming sub-goal file from a description | met |
| 3 | Both outputs marked draft-for-review | met (DRAFT marker on line 1 of each) |
| 4 | Run-table records the lint passes | met (below) |
| 5 | The subagent never self-installs; the command installs by DEFAULT (Han 2026-07-01: runtime-ready, not draft-only), `--draft` opt-out | met (subagent writes to staging only; the command strips marker -> `agents/<name>.md` -> roster-sync -> `test-meta.sh` -> `cp` to `~/.claude/agents/`; install-promotion simulated in the test) |
| 6 | **Mode C: same-run specialist dispatch** (Han 2026-07-01). `/kit:execute` auto-classifies each task; a specialist-worthy task gets a synthesized role PREAMBLE injected into its worker NOW (no next-session file), cached to `~/.claude/agents/` for reuse | met (meta-agent Mode C returns NAME/TOOLS/PREAMBLE inline; execute.md 2b-0 classify -> Mode C -> inject -> cache, generic fall-through preserved; golden fixture `inline-role-spec.txt` proves a concrete security preamble; 6 structural + 6 fixture assertions) |

## Implementation

- `agents/meta-agent.md` , the gated "agent that builds agents". Two modes (subagent / sub-goal file), determines minimal tools, matches the kit's exact frontmatter, marks output DRAFT, never installs.
- `commands/draft-agent.md` , `/kit:draft-agent` verb that dispatches it to a staging path and stops at the draft.
- `tests/test-meta-agent.sh` , lints the meta-agent definition + the two committed golden drafts.
- `tests/fixtures/meta-agent/{drafted-agent,drafted-subgoal}.md` , the golden outputs the drafter actually produced (the run that proves it works).
- Roster sync (required by the kit's own anti-drift guards): `MANUAL.md` row, `docs/architecture.md` inventory rows, `README.md` command count + row.

## Confirmation run-table

The drafter was run on two one-line descriptions, producing the two committed fixtures, which then pass the lint:

| Mode | Input description | Output | name / Done= | Lint |
|---|---|---|---|---|
| A (subagent) | "read-only agent that audits GitHub Actions workflows for hardcoded secrets + over-broad permissions" | `tests/fixtures/meta-agent/drafted-agent.md` | name `workflow-secrets-auditor`, tools `Read,Grep,Glob` (minimal, read-only), model `sonnet` | pass |
| B (sub-goal) | "add exponential-backoff retry to the API client for transient 429/5xx" | `tests/fixtures/meta-agent/drafted-subgoal.md` | Done= "four retry tests pass ... + 400 negative-control shows one attempt, both rows in the run-table" | pass |

```
$ bash tests/test-meta-agent.sh
=== meta-agent definition ===     11 PASS
=== golden draft: subagent ===     8 PASS
=== golden draft: sub-goal file === 19 PASS
=== 38/38 passed, 0 failed ===     EXIT 0
```

## Negative control / regression

The new agent + command must satisfy the kit's OWN structural guards, not just my test. Running the kit's full structural suite with the additions in place:

```
$ bash tests/test-meta.sh
Passed: 508 / 508   All meta tests passed.
```

This confirms the cross-ref guards fired correctly: `agents/meta-agent.md` is linted by the same `name/description/model` checks as every kit agent, requires its `MANUAL.md` row, and the `architecture.md` inventory + `README.md` command counts were updated to match (the suite fails closed if any is missing , verified by seeing exactly those 3 drift-rows FAIL before the roster sync, then pass after).

## Reproduce

```bash
cd <kit-worktree>
bash tests/test-meta-agent.sh    # 38/38, lints the definition + golden drafts
bash tests/test-meta.sh          # 508/508, the kit's own guards accept the new roster
```

To regenerate a fresh draft (live): `/kit:draft-agent agent: <one-line role>` or
`/kit:draft-agent subgoal: <one-line unit of work>`.
