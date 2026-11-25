# Team workflow

How a small team ships fast with AI agents and still stays in sync. This page gives the reasons. The rules themselves live in [`AGENTS.md`](../AGENTS.md), one home for agents and people alike. Each rule below links to its section there.

## Why

- Everyone builds with an AI agent. Work starts at the keyboard, not in a meeting.
- Nobody waits for an owner. Every teammate shares the product, so every idea counts.
- Stand-ups and plan-first talks cost more than they give, so the way to stay in sync changes: sync on running things after the work, not on talk before it.
- A rule that only one person's tools enforce binds that person and nobody else. These rules ride in the repo, so they bind every agent and every teammate.

## The loop

```
 idea --> claim an issue --> build with AI --> PR = the proposal --> merge when green
            (30 s)            (no meeting)     (proof + changelog)     (no approval)
              |                                   |                     |
              v                                   v                     v
        issue shows who                 PR closes its issue     digest by script
        builds what                     and carries its proof

                      one-way doors only ---> a second person says yes
```

## The rules

Each rule gives the reason. The rule itself, with its conditions, marker lines and commands, lives in `AGENTS.md` and nowhere else. Follow the link.

### 1. Claim first

GitHub Issues are the work queue. One issue is one unit of work for one agent run, with a goal and a check that says it is done.

Why: a claim takes 30 seconds and shows the whole team who builds what. Two people on the same task is the cost of skipping it. A stale claim blocks others, so an old one is released.

The rule: [Work queue](../AGENTS.md#work-queue).

### 2. Reversible work merges without an approver

Merge your own PR when the checks pass. Nobody approves it. Reversible means a revert undoes it: code, docs, tests, a prototype behind a flag.

Why: waiting for a person is the delay this workflow removes. A revert is cheap, a wait is not. Not sure it is reversible? Treat it as a one-way door (rule 3).

Merge with `bash scripts/pr-merge.sh --wait <number>`, never a bare `gh pr merge`. The script waits for the checks and refuses a draft, a red or pending check, a conflict, and a change under a door path without a second person's yes.

The rule: [Merge](../AGENTS.md#merge) and [Checks](../AGENTS.md#checks).

### 3. One-way doors need a second person's yes

A one-way door is hard to undo after it ships. A charged customer cannot be un-charged. A lawyer reads the legal text and people rely on it. A shipped client cannot be recalled. Deleted data does not come back. A leaked key cannot be taken back. For these, a second person says yes first. The author never counts as the second person.

| Door setting | Value |
|---|---|
| Paths the merge guard checks | {{DOOR_PATHS}} |
| Who says the second yes for those paths | {{DOOR_APPROVER}} |

A blank path cell means the guard lists no path: the `One-way door:` line in the PR and the reviewer are the control. A blank approver cell means any person other than the author.

Agents follow the same list. An agent stops and asks a human before it touches secrets or access.

The rule: [One-way doors](../AGENTS.md#one-way-doors) and [Never](../AGENTS.md#never).

### 4. The PR carries its own bookkeeping

Ask your agent to do all of this in the same PR. Nobody files it later: later does not happen. The PR closes its issue, fixes the docs the code made wrong, and carries its proof and its changelog line.

Why: a proof you did not run is the agent's word. The proof file and its negative control make "done" something a second person can re-run. The changelog line makes the next release note write itself. Tags in use: {{TAGS}}. The tag `dev` marks team tooling and stays out of the release notes.

The rules: [What a PR carries](../AGENTS.md#what-a-pr-carries), [Proof](../AGENTS.md#proof) and [Changelog](../AGENTS.md#changelog). Product code lives under {{PRODUCT_PATHS}}.

### 5. A digest replaces the stand-up

One script reads GitHub and the board file and prints a short markdown page. No meeting, no status chat. See "Digest" below.

Every script and job has an owner, a person or a named agent with a sponsor, so a broken one is never nobody's problem. The rule: [Checks](../AGENTS.md#checks).

## What a good PR looks like

The PR is the proposal. The reader should know in one minute what it does and that it works. The PR template has a section for each part.

| Part | What goes in |
|---|---|
| Closes | `Closes #<n>`, the issue that holds the work |
| Proof | A proof file with a negative control. Run it yourself, do not trust the agent's word. See [Proof](../AGENTS.md#proof) |
| Changelog | A tagged line under `[Unreleased]` for product code |
| One-way door line | Only when the PR touches a door in rule 3 |

How to write the proof: [`verification/README.md`](verification/README.md). The one local check before a push: `bash scripts/check.sh`. The commands by area: [Commands](../AGENTS.md#commands).

## When ideas collide

Two people want different things for the same part of the product.

1. Each builds a small prototype on their own branch. Claim an issue each, with a note that points at the other.
2. Neither merges. Both show the running prototype to the team.
3. The team picks one. If the team cannot, the owner picks.
4. The loser's PR closes with a short note.

Do not argue in a thread first. A demo settles it faster.

## Digest

```
bash scripts/team-digest.sh              # last 24 hours
bash scripts/team-digest.sh --hours 72   # after a weekend
```

- It needs only `gh` (logged in) and the standard tools. It writes markdown to stdout and posts nothing.
- It shows: PRs merged in the window, open PRs, open issues with assignee, and the board rows that wait on a human decision.
- Read it instead of a stand-up. Reply in the PR or the issue, not in a meeting.

## From board rows to issues

After the board file changes, whoever merged it runs `bash scripts/issues-from-rows.sh` for a dry run, then `--apply`. It makes one issue per queued, tagged, ready row, and a rerun creates nothing twice. Then each person hands their issues to their own agents: `gh issue list --assignee @me --label ready --state open`. The issue's Done when is the finish check.

## Limits

GitHub cannot enforce any of this without branch protection. A person who merges from the GitHub site passes everything, on a plan without branch protection.

Two machines back the rules instead: a Claude Code hook for the agents that run in it, and the CI check `pr-shape` for everyone. The hook is advice with teeth, not a wall. Claude Code uses a hook from `.claude/settings.json` even in a folder not yet trusted (only a parent folder trusted, or a `claude -p` run), so a teammate needs no extra step. Agents other than Claude Code meet only the CI check.

The rule: [Limits](../AGENTS.md#limits).

## Optional kit

The owner may use dwarves-kit on a machine. Nothing here needs it, and it is not part of these rules. The closing section of `AGENTS.md` says what to know: [Optional kit](../AGENTS.md#optional-kit).

## Rule index

Every section of `AGENTS.md` has its anchor here, so a change to one shows up in the other. The check `scripts/pr-shape.sh` keeps the two files in step.

- [Agent rules](../AGENTS.md#agent-rules)
- [Commands](../AGENTS.md#commands)
- [Playbooks](../AGENTS.md#playbooks)
- [Lessons](../AGENTS.md#lessons)
- [Team rules](../AGENTS.md#team-rules)
- [Work queue](../AGENTS.md#work-queue)
- [What a PR carries](../AGENTS.md#what-a-pr-carries)
- [Proof](../AGENTS.md#proof)
- [Changelog](../AGENTS.md#changelog)
- [One-way doors](../AGENTS.md#one-way-doors)
- [Merge](../AGENTS.md#merge)
- [Checks](../AGENTS.md#checks)
- [Limits](../AGENTS.md#limits)
- [Never](../AGENTS.md#never)
- [Optional kit](../AGENTS.md#optional-kit)
