# Spec: team stamp, a kit-free agent harness written into a repo
Generated: 2026-11-25
Status: DRAFT
Lane: full (the build adds a verb that writes enforcement scripts, a hook, a CI workflow and a merge guard into other people's repos)
Depth: research (repo: how adopt writes, hashes and refuses today, and what the hand-fitted repo's files really contain) + research (outside: the current Claude Code hook and skill contracts, fetched, not recalled)
Type: spec-feature
File: `docs/specs/SPEC-425-team-stamp.md`
References: `lib/adopt.sh` (imitate: never overwrite, hash-decided drift line, jq MERGE into `.claude/settings.json`, symlink refusal through `lib/config/safe-path.sh`, `--check`/`--dry-run`/`--refresh`); `lib/adopt/known-hashes.sh` (imitate: the known-hash list is regenerated from history, never typed); `lib/gate/negctl.sh` (the kit's negative control; the stamped `scripts/negctl.sh` is its kit-free sibling, see Decision DEC-6); `commands/gauntlet.md` (the engine that records the Done run); `docs/briefs/DECISION-BRIEF-team-stamp.md` (the design contract, build step 3).

## Problem

One operator runs the kit. Three teammates do not, and their coding agents do most of the work. A private product repo was fitted by hand (about twenty files over two days) and the teammates' agents then followed the rules with no kit: four PRs arrived with a proof file, a board link and a tagged changelog line, and CI caught the one rule an agent missed.

The kit cannot produce that harness. `adopt` writes a pointer that sends an agent to a path under the kit, and every kit gate runs only where the plugin is installed. A rule that lives only in the kit binds the operator and nobody else. Doing the hand fit again for the next repo costs two days and drifts from the first copy.

## Terms

- stamp: the verb `lib/stamp.sh` and the set of plain files it writes. The files are repo-owned copies. After the write the kit has no part in them.
- kit-free: a generated file reads, runs and tests with no kit on the machine: no kit path in its text, no kit binary on `PATH`, no kit directory under `HOME`.
- lock: `.claude/team-stamp.lock`, the stamp's own record of what it wrote (stamp version, parameter values, one sha256 per file). It is plain text and kit-free. It exists so "the repo edited this file" can be told from "this is an older stamp copy" (see DEC-3).
- door: a path list where a change needs a second person's approval before merge.
- twin: `scripts/check.sh`, the local script that runs the CI job's checks with the same inputs.

Canonical home for new terms: the repo glossary `CONTEXT.md` (stamp, kit-free, lock, door, twin), written with this spec.

## Solution

### Approaches considered

1. A new verb `lib/stamp.sh` next to `lib/adopt.sh`, with the files as templates under `templates/team-stamp/`, rendered with a small value set. Tradeoff: one more verb and about 45 template files to keep true; the generated files are plain, so the kit never needs to be present after the write.
2. Extend `adopt` with `--team`. Tradeoff: `adopt` is the kit-pointer verb and the adopt-pointer row is changing it right now; a second personality in one 645-line script doubles its refusal surface, and a stamp must work on a repo the kit never adopted.
3. A template repo or `gh repo create --template`. Tradeoff: fixes only new repos, carries no drift report and no upgrade path, and a template repo is one more thing to keep current.

### Chosen approach + why

Approach 1. The brief says "a new verb next to adopt". It shares adopt's discipline (never overwrite, hash-decided drift, jq merge, symlink refusal) by copying the shape, not by sourcing adopt's code, so the pointer worker's edits to `lib/adopt.sh` cannot break it and it cannot break them. The one shared surface is the first line of `AGENTS.md` (the kit marker): the stamp reads line 1 of `lib/adopt/AGENTS.pointer.md` at stamp time and refuses if that line does not start with `<!-- kit:agents-pointer`. That is read-only and survives the pointer rewrite.

### Extensibility & boundaries

- The dimension that grows is the file set: a new generic piece is one template plus one manifest row plus its test, in its own `manifest.d/NN-<group>.tsv`. The engine knows no file by name.
- Units: `lib/stamp.sh` (arguments, values, render, write, lock, drift, refresh), `templates/team-stamp/` (content only), `manifest.d/*.tsv` (what goes where). A template never contains logic the engine needs; the engine never contains repo-rule text.

## Picture

```
 operator, with the kit                       teammate's agent, no kit
 ─────────────────────                        ──────────────────────────
 bash lib/stamp.sh [flags] <repo>
        │ reads
        v
 templates/team-stamp/                              (stamp writes once, then steps out)
   manifest.d/*.tsv  files/**  ──render values──>  <repo>/
        │                                            AGENTS.md  docs/TEAM-WORKFLOW.md   L1 advice
        │ jq merge (never rewrite)                   .claude/settings.json ──┐
        v                                            scripts/agent-guard.sh <┘            L2 hook
   .claude/team-stamp.lock (sha256 per file)         scripts/agent-lessons.sh .claude/memory/
                                                     .github/workflows/ci.yml             L3 CI
                                                     scripts/{pr-shape,check,check-owners,
                                                       pr-merge,negctl,issues-from-rows,
                                                       release-notes,team-digest}.sh      L3/L4
                                                     OWNERS.md CHANGELOG.md .kit.toml ...

 refusal at L2 or L3:        <tool>: <the rule, one line>
                             Fix: <the command, next line>
```

## Design

### Vendor contract (fetched 2026-11-25, not recalled)

Sources: https://code.claude.com/docs/en/hooks and https://code.claude.com/docs/en/skills. Both fetches succeeded; each page was larger than one read (hooks 293,835 characters, skills 121,231), so each answer below says which part was read. A statement the fetch did not show is marked UNCONFIRMED and the build re-reads it before relying on it.

| Generated file depends on | Contract text (verbatim where quoted) |
|---|---|
| `.claude/settings.json` structure | `hooks` > event name > list of matcher groups, each `{ "matcher": "Bash", "hooks": [ { "type": "command", "command": "<shell command>" } ] }`. `type` is one of `command`, `http`, `mcp_tool`, `prompt`, `agent`. The page example uses `${CLAUDE_PROJECT_DIR}/.claude/hooks/block-rm.sh` as the command. |
| project root variable | "`${CLAUDE_PROJECT_DIR}`: the project root where the session started." In a linked worktree it "still points at the project root where the session started", so the stamped scripts resolve the repo from the hook's `cwd` field when they need the worktree. |
| `scripts/agent-guard.sh` input | The hook receives JSON on stdin with common fields `session_id`, `cwd`, `permission_mode`, `transcript_path`, `hook_event_name`, and for PreToolUse "The `tool_name`, `tool_input`, and `tool_use_id` fields are event-specific." For Bash, `tool_input.command` is "The shell command to execute". |
| `scripts/agent-guard.sh` decision | "**Blocking error**: your hook exits 2. On events that can block, Claude Code stops the action." For PreToolUse, "A hook that blocks by exiting 2 routes the same way as `deny`: Claude sees the stderr message as the denial reason." Exit 0 with no output "means no decision; normal permission flow applies." "Claude never sees stderr from a hook that exits 0." Any other exit code is a non-blocking error: the action goes ahead. Structured form: `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` ("`deny` prevents the tool call"; the reason "shown to Claude"). The stamp uses exit 2 with the two lines on stderr, so the guard needs no JSON writer and works with `jq` absent. |
| `scripts/agent-lessons.sh` output | SessionStart "Claude Code adds plain-text stdout as context that Claude can see and act on." Its matcher filters on `source`: `startup`, `resume`, `clear`, `compact`, `fork`. "A hook's `additionalContext`, `systemMessage`, and `initialUserMessage` strings, and its plain stdout, are capped at 10,000 characters." Over the cap, "Claude Code saves the output to a file in the session directory" and shows a path plus a preview of "up to the first 2,000 characters", and "doesn't ask Claude to read the file". The generated `MEMORY.md` index therefore stays under 8,000 characters and `agent-lessons.sh` truncates with a notice at 9,000. |
| `.claude/skills/ship-pr/SKILL.md` | Project path `.claude/skills/<skill-name>/SKILL.md`, loaded in "Sessions in this repository" ("Commit it so your team gets it too"). Frontmatter is read "only when the opening `---` is the file's first line". Fields: `name` ("Defaults to the directory name"), `description` ("What the skill does and when to use it"; description plus `when_to_use` is "truncated at 1,536 characters"), `disable-model-invocation`, `user-invocable`, `allowed-tools`. "Claude Code ignores a field it doesn't recognize without reporting an error", so a misspelled key fails silently and the test must check the exact key names. "Only `description` is recommended." The skill ships with `name` and `description` only: no `allowed-tools` (a project skill's `allowed-tools` applies even in a folder never trusted, so the stamp grants none). |
| UNCONFIRMED | Whether a project `settings.json` hook runs before the teammate trusts the folder. The fetched text said only that frontmatter hooks in a project skill "follow the same workspace trust rule as hooks in settings files" and that a project subagent's hooks "run only after you accept the workspace trust dialog". The linked "What runs before you trust a folder" section was not in the text read. The build re-reads it; until then the generated `AGENTS.md` and `TEAM-WORKFLOW.md` say "a teammate trusts the folder once before the hook loads" as an expected step, and the proof lists it under what was not shown. |

### Generated files

One row per brief table row. "Value" names the stamp parameter the file takes; "agnostic" means byte-identical in every repo. Source templates live under `templates/team-stamp/files/<target path>` (a `.tpl` suffix when the file takes a value). Each script's test is generated beside it as `scripts/test-<name>.sh` and is itself kit-free. Kit-side tests are `tests/test-stamp-<group>.sh`.

| # | Brief row | Target path | Source template | Generated test | Agnostic or value | Group |
|---|---|---|---|---|---|---|
| 1 | Agent rules | `AGENTS.md` | `files/AGENTS.md.tpl` | `tests/test-stamp-rules.sh` (kit side: line 1 marker, section anchors, no kit path, closing section) | value: default branch, door table, tags, product paths | G1 |
| 2 | People's copy | `docs/TEAM-WORKFLOW.md` | `files/docs/TEAM-WORKFLOW.md.tpl` | `tests/test-stamp-rules.sh`; parity run by `scripts/test-pr-shape.sh` | same values as row 1 | G1 |
| 3 | Command guard | `scripts/agent-guard.sh` | `files/scripts/agent-guard.sh.tpl` | `scripts/test-agent-guard.sh` | value: default branch | G3 |
| 4 | Command guard | `.claude/settings.json` | `files/.claude/settings.json` (merge snippet) | `tests/test-stamp-hook.sh` (merge keeps foreign keys, idempotent) | agnostic | G3 |
| 5 | Lessons | `scripts/agent-lessons.sh` | `files/scripts/agent-lessons.sh` | `scripts/test-agent-lessons.sh` | agnostic | G2 |
| 6 | Lessons | `.claude/memory/MEMORY.md` plus five seed notes | `files/.claude/memory/*.md` | `scripts/test-agent-lessons.sh` (index links resolve, size under cap) | agnostic | G2 |
| 7 | Playbook | `.claude/skills/ship-pr/SKILL.md` | `files/.claude/skills/ship-pr/SKILL.md.tpl` | `tests/test-stamp-playbook.sh` (frontmatter keys exact, every command in it exists as a generated script) | value: default branch | G9 |
| 8 | PR shape | `scripts/pr-shape.sh` | `files/scripts/pr-shape.sh.tpl` | `scripts/test-pr-shape.sh` | value: tags, product paths, board file, default branch | G8 |
| 9 | PR shape | `.github/workflows/ci.yml` | `files/.github/workflows/ci.yml.tpl` | `scripts/test-check.sh` (twin parity), `actionlint` when present | agnostic: always `runs-on: [self-hosted]` | G8 |
| 10 | Local check | `scripts/check.sh` | `files/scripts/check.sh.tpl` | `scripts/test-check.sh` | value: tags, product paths | G8 |
| 11 | Owners | `OWNERS.md` | `files/OWNERS.md.tpl` | `scripts/test-check-owners.sh` | value: owner login; rows seeded for every generated script | G4 |
| 12 | Owners | `scripts/check-owners.sh` | `files/scripts/check-owners.sh` | `scripts/test-check-owners.sh` | agnostic | G4 |
| 13 | Merge guard | `scripts/pr-merge.sh` | `files/scripts/pr-merge.sh.tpl` | `scripts/test-pr-merge.sh` | value: default branch, door paths, door approver login | G7 |
| 14 | Negative control | `scripts/negctl.sh` | `files/scripts/negctl.sh` | `scripts/test-negctl.sh` | agnostic | G7 |
| 15 | Work queue | `.github/ISSUE_TEMPLATE/task.yml` | `files/.github/ISSUE_TEMPLATE/task.yml` | `tests/test-stamp-queue.sh` (YAML parses, section ids match what the script reads) | agnostic | G5 |
| 16 | Work queue | `scripts/issues-from-rows.sh` | `files/scripts/issues-from-rows.sh.tpl` | `scripts/test-issues-from-rows.sh` | value: board file | G5 |
| 17 | Work queue | `.github/pull_request_template.md` | `files/.github/pull_request_template.md` | `tests/test-stamp-queue.sh` (carries `Closes #`) | agnostic | G5 |
| 18 | Changelog | `CHANGELOG.md` (tag list, `[Unreleased]`) | `files/CHANGELOG.md.tpl` | `scripts/test-release-notes.sh` | value: tags | G6 |
| 19 | Changelog | `scripts/release-notes.sh` | `files/scripts/release-notes.sh.tpl` | `scripts/test-release-notes.sh` | value: tags (the team-tooling tag is `dev`) | G6 |
| 20 | Digest | `scripts/team-digest.sh` | `files/scripts/team-digest.sh.tpl` | `scripts/test-team-digest.sh` | value: decision tag | G9 |
| 21 | Proof guide | `docs/verification/README.md` | `files/docs/verification/README.md.tpl` | `tests/test-stamp-rules.sh` | agnostic | G1 |
| 22 | Gate config | `.kit.toml` | `files/.kit.toml` | `tests/test-stamp-rules.sh` (`proof_of_done = true`, `lane_gates = false`) | agnostic | G1 |

Not generated, because the brief's table does not list them: the board-ID mint script, the doc-link check, evidence-branch rules, and any language job. The workflow carries stub language jobs as comments only (the brief: language test jobs are left to the repo).

Parameters, set by flags and recorded in the lock:

| Flag | Default | Used by |
|---|---|---|
| `--default-branch` | `git symbolic-ref refs/remotes/origin/HEAD`, else `main`, else refuse | rows 1, 2, 3, 7, 8, 13 |
| `--owner <login>` | none: refuse with the fix line | row 11 |
| `--tags a,b,c` | `product,dev` (`dev` is always present and is the team-tooling tag) | rows 1, 8, 10, 18, 19 |
| `--product-paths a/,b/` | `src/` | rows 8, 10 |
| `--door-paths a,b` and `--door-approver <login>` | empty door list: the second-person rule is written, listing no path | row 13, rows 1, 2 |
| `--board-file <path>` | empty: only `Closes #n` and `no-board-row:` satisfy the board link | rows 8, 16 |

### Interplay with adopt (the second reader of the same files)

| File | Stamp first, adopt later | Adopt first, stamp later |
|---|---|---|
| `AGENTS.md` | adopt sees an existing file and leaves it (its line 1 is the kit marker, so `is_adopted` holds) | stamp sees a file that is the kit pointer or an old kit copy by hash: it reports it, writes nothing, and prints `Fix: bash lib/stamp.sh --take AGENTS.md <repo>` which replaces only a file whose hash is a known kit pointer |
| `docs/verification/README.md` | adopt leaves the stamp's guide (it never overwrites the marker) | the file is adopt's four-line marker: same rule as `AGENTS.md`, `--take` swaps it for the guide; any other content is a drift line |
| `.kit.toml` | adopt never overwrites; the stamp's `lane_gates = false` stands | the file has `lane_gates = true`: drift line plus `Fix: set lane_gates = false in .kit.toml`; never edited by the stamp |
| `.claude/settings.json` | adopt's jq merge adds kit hooks beside the stamp's two | the stamp's jq merge adds its two entries beside the kit's; both keep each other's keys |
| `CLAUDE.md` | the stamp writes none (agents-only shape); adopt's loader is its own | untouched |

A stamp run never edits adopt's managed `<!-- kit:adopt -->` block.

## Technical Design

### Interfaces (I/O contract)

- Inputs: `lib/stamp.sh [--check | --dry-run | --refresh | --take <path>] [flags above] <target-dir>`. `--check` exits 0 when every manifest file exists and matches the lock, else 1, writing nothing. `--dry-run` prints what would be written. Default (no mode flag) writes missing files only. `--refresh` writes nothing and prints, per file whose template changed since the lock, a unified diff and `Fix: bash lib/stamp.sh --take <path> <repo>`. `--take <path>` replaces exactly one file, and only when the file's current hash equals its lock hash (unedited); the old content is first copied to `<path>.orig`. For an edited file `--take` refuses and prints the diff between the lock's rendering and the new template with `Fix: apply the diff above by hand`; the stamp never replaces an edited file.
- Outputs: the files in the table, `.claude/team-stamp.lock`, and report lines `created`, `unchanged`, `edited (left alone)`, `older stamp (run --refresh)`, `missing`.
- Invariants: no write outside the target; no write through a symlink (`kit_refuse_symlink_path` over every target path and its parents); a failed run leaves the tree as found (write to a temp name, then rename); no generated file contains a path under the kit; a re-run with the same inputs prints only `unchanged`.

### Data model changes

The lock, one file, plain text, parseable with `awk`:

```
stamp-version 1
value default-branch main
value owner <login>
...
file <path> <template-id> <sha256 as written>
```

### Where the verb lives, and why

`lib/stamp.sh` with a `# kit-verb: stamp | ...` header, `lib/stamp/README.md`, `templates/team-stamp/`, and `commands/stamp.md` (`/kit:stamp`). This is how adopt is wired: `lib/adopt.sh` carries a `# kit-verb:` header that `lib/registry/feature-registry.sh` reads into `docs/reference/FEATURES.md`; the human door is `commands/adopt.md`; there is no `bin/` entry and no `lib/config/modules.tsv` row (adopt is "no install module" in `lib/config/module-registry.md`). The stamp has no hook of its own and no kit knob, so it gets no module row either. `wrap adopt` composes adopt for a fleet; a `wrap stamp` is out of scope (see Out of Scope).

### Generator rules as behavior

1. Kit-free output: the render step scans every rendered file for the kit-path patterns below before writing and aborts the whole run on a hit. Patterns: `\.claude/dwarves-kit`, `CLAUDE_PLUGIN_ROOT`, `KIT_ROOT`, `lib/gate/`, `/bin/(gate|classify|wrap|board)`, and any absolute path under the operator's home. The only allowed kit text is line 1 of `AGENTS.md` (the marker) and the one public URL `https://github.com/dwarvesf/dwarves-kit` in `AGENTS.md`'s closing "if the kit is installed" section, which names no local path.
2. Refusal text: every refusal prints exactly two lines, first `<tool>: <the rule in one line>`, then `Fix: <the command>`. The rule line says what is forbidden and why in plain words; the fix line is a command that can be pasted. pr-shape prints one pair per failed check. The kit-side test `tests/test-stamp-refusals.sh` runs every refusal in the generated scripts and asserts `^Fix: ` is the line right after the rule line.
3. Runner label: the generated workflow always has `runs-on: [self-hosted]` and never a GitHub-hosted label (`ubuntu-*`, `macos-*`, `windows-*`); a test on the template text pins that. A repo with a named pool edits its own file, and the stamp then reports it as edited and leaves it. Why: the estate rule is zero hosted-runner spend, and the org template "CI (self-hosted)" is the same shape. A repo with no self-hosted runner gets a workflow that queues and never starts, which costs nothing and fails closed; the twin `scripts/check.sh` is how a PR is checked until a runner exists.
4. Shellcheck in CI: no hosted image can be assumed to have it. The job installs a pinned release and checks its sha256 before use, picking the asset by `uname -m` (the hand-fitted job pinned one architecture only). The build fetches both digests from the release metadata with `gh api` and records the release tag in the template; no digest is typed from memory.
5. Idempotence: all writes go through one `write_if_absent` and one lock update. Two runs in a row produce no diff (`git status --porcelain` empty on the second).
6. Drift: for each manifest file the stamp compares three hashes: current file, lock, and the rendered template. Current != lock means the repo edited it (`edited (left alone)`, with the line count that differs). Current == lock != template means an older stamp copy (`older stamp`). Missing means `missing` and the file is re-created on a default run only when the lock never listed it.
7. Upgrade offer: `--refresh` prints one unified diff per `older stamp` file and the `--take` command for it. It never applies any.

### Task split for the build

Groups are independently testable and in dependency order. Files in a group are disjoint from every other group's (each group owns its own `manifest.d/NN-<group>.tsv`, so no shared manifest file), so groups on the same rung can build in parallel in separate worktrees.

```
G0 engine ──┬─ G1 rules docs ──────────────┐
            ├─ G2 lessons                  │
            ├─ G3 hook                     │
            ├─ G4 owners ──────────────────┤
            ├─ G5 queue ───────────────────┼─ G8 CI layer ── G10 integration ── G11 gauntlet run
            ├─ G6 changelog ───────────────┤
            ├─ G7 merge guard, negctl      │
            └─ G9 playbook, digest ────────┘
```

Rung 1: G0 alone. Rung 2 (parallel, disjoint): G1, G2, G3, G4, G5, G6, G7, G9. Rung 3: G8 (needs G1 anchors, G4 owners script, G5 and G6 conventions it checks). Rung 4: G10. Rung 5: G11.

## Task Breakdown

### Phase 1: Foundation

- [ ] TASK-G0 engine (parallel: no). Files: `lib/stamp.sh`, `lib/stamp/README.md`, `tests/test-stamp.sh`, `tests/test-stamp-kitfree.sh` (a harness callable as `bash tests/test-stamp-kitfree.sh <group>`), `tests/fixtures/team-stamp/` (a two-file fixture manifest). Done when: render with `{{KEY}}` values, `write_if_absent`, lock write, `--check`, `--dry-run`, `--refresh`, `--take`, jq merge for `.claude/settings.json`, symlink refusal, kit-path scan, the lock's three-hash drift report, all against the fixture. Test: `bash tests/test-stamp.sh && bash tests/test-stamp-kitfree.sh fixture`.

### Phase 2: Pieces (rung 2, all parallel)

- [ ] TASK-G1 rules docs. Files: `templates/team-stamp/files/AGENTS.md.tpl`, `files/docs/TEAM-WORKFLOW.md.tpl`, `files/docs/verification/README.md.tpl`, `files/.kit.toml`, `manifest.d/10-rules.tsv`, `tests/test-stamp-rules.sh`. Done when: line 1 of `AGENTS.md` equals line 1 of the pointer template; sections commands, playbooks, lessons, team rules, never, closing optional-kit section with a public URL and no local path; every `AGENTS.md` heading has a matching anchor in `TEAM-WORKFLOW.md`; the proof guide states the `Command:`, `Output:`, `Exit:`, `NEGATIVE CONTROL`, `Verdict:` shape; `.kit.toml` sets `proof_of_done = true` and `lane_gates = false`; the limit sentence (a merge from the GitHub site passes everything on a plan without branch protection) is present in both docs. Test: `bash tests/test-stamp-rules.sh`.
- [ ] TASK-G2 lessons. Files: `files/scripts/agent-lessons.sh`, `files/scripts/test-agent-lessons.sh`, `files/.claude/memory/MEMORY.md`, five seed notes under `files/.claude/memory/` (runner image has no procps, `CI=true` changes script behavior, queued run missing from filtered lists, a guard matches command text only, green checks go stale after a rule change), `manifest.d/20-lessons.tsv`, `tests/test-stamp-lessons.sh`. Done when: the script prints the index, exits 0 when it is missing, truncates with a notice past 9,000 characters; each note has `name` and `description` frontmatter and is under 1,200 characters with no personal names. Test: `bash tests/test-stamp-lessons.sh`.
- [ ] TASK-G3 hook. Files: `files/scripts/agent-guard.sh.tpl`, `files/scripts/test-agent-guard.sh`, `files/.claude/settings.json`, `manifest.d/30-hook.tsv`, `tests/test-stamp-hook.sh`. Done when: the guard blocks (exit 2, two lines on stderr) a bare `gh pr merge`, a push to the default branch (`git push origin main`, `git push origin HEAD:main`, `git push` while on it), a commit on the default branch; allows `bash scripts/pr-merge.sh --wait 5`, `echo "gh pr merge"`, a feature-branch push and commit; reads JSON with `jq`, else `python3`, else allows with a one-line note; any internal failure exits 0; the settings merge adds a PreToolUse `Bash` entry and a SessionStart entry using `${CLAUDE_PROJECT_DIR}` and keeps foreign keys. Test: `bash tests/test-stamp-hook.sh`.
- [ ] TASK-G4 owners. Files: `files/OWNERS.md.tpl`, `files/scripts/check-owners.sh`, `files/scripts/test-check-owners.sh`, `lib/stamp/owners-seed.sh`, `manifest.d/40-owners.tsv`, `tests/test-stamp-owners.sh`. Done when: the check fails (two-line refusal) on a tracked script, workflow or job with no row, a row pointing at a missing path, an empty owner, an agent owner with no sponsor; `owners-seed.sh` runs after every other group's files exist and adds one row per generated script. Test: `bash tests/test-stamp-owners.sh`.
- [ ] TASK-G5 queue. Files: `files/.github/ISSUE_TEMPLATE/task.yml`, `files/.github/pull_request_template.md`, `files/scripts/issues-from-rows.sh.tpl`, `files/scripts/test-issues-from-rows.sh`, `manifest.d/50-queue.tsv`, `tests/test-stamp-queue.sh`. Done when: the form writes `Goal`, `Done when`, `Scope`, optional `Notes`; the script turns board rows into issues with `gh` faked in the test, one issue per row, idempotent on a second run, labels `ready`, `one-way-door`, `blocked`; the PR template has a `Closes #` line. Test: `bash tests/test-stamp-queue.sh`.
- [ ] TASK-G6 changelog. Files: `files/CHANGELOG.md.tpl`, `files/scripts/release-notes.sh.tpl`, `files/scripts/test-release-notes.sh`, `manifest.d/60-changelog.tsv`, `tests/test-stamp-changelog.sh`. Done when: `[Unreleased]` carries the tag list; release notes drop `dev:` lines and refuse an untagged line with a two-line refusal. Test: `bash tests/test-stamp-changelog.sh`.
- [ ] TASK-G7 merge guard and negctl. Files: `files/scripts/pr-merge.sh.tpl`, `files/scripts/test-pr-merge.sh`, `files/scripts/negctl.sh`, `files/scripts/test-negctl.sh`, `manifest.d/70-merge.tsv`, `tests/test-stamp-merge.sh`. Done when: with `gh` faked, the guard waits for checks, refuses a draft, a red check, a pending check at timeout, a conflict, and a change under a door path without a second person's approval (the author never counts as the second person), merges a clean PR pinned to the judged head, and `--dry-run` merges nothing; `negctl.sh` runs green, break, red, restore, green, refuses a dirty tree before mutating, refuses a "red" that is only a load or syntax error, and prints a block with `Command:`, `Output:`, `Exit:`, `NEGATIVE CONTROL`, `Verdict:`. Test: `bash tests/test-stamp-merge.sh`.
- [ ] TASK-G9 playbook and digest. Files: `files/.claude/skills/ship-pr/SKILL.md.tpl`, `files/scripts/team-digest.sh.tpl`, `files/scripts/test-team-digest.sh`, `manifest.d/90-digest.tsv`, `tests/test-stamp-playbook.sh`. Done when: SKILL.md starts with `---` on line 1, has exactly `name` and `description`, and every `bash scripts/...` command in it names a script in the manifest; the digest prints merged PRs, open PRs, open issues with assignee, and decisions waiting, from a faked `gh`, and exits 0 with a note when `gh` is absent. Test: `bash tests/test-stamp-playbook.sh`.

### Phase 3: CI layer (rung 3)

- [ ] TASK-G8 CI layer. Files: `files/scripts/pr-shape.sh.tpl`, `files/scripts/test-pr-shape.sh`, `files/scripts/check.sh.tpl`, `files/scripts/test-check.sh`, `files/.github/workflows/ci.yml.tpl`, `manifest.d/80-ci.tsv`, `tests/test-stamp-ci.sh`. Done when: pr-shape checks conventional title, proof file with a `Verdict: RED` negative-control block for a behavior change (or `no-proof:` with a 10+ character reason), board link (`Closes #n`, board file changed, or `no-board-row:`), tagged changelog line for product paths (or `no-changelog:`), shellcheck on changed shell files (a missing shellcheck is a skip with a notice locally and a failure when `CI=true`), and rule parity (a PR that changes `AGENTS.md` or `docs/TEAM-WORKFLOW.md` and not the other fails unless the body has `no-rule-mirror:`); the workflow has jobs `changes` (owners check, path filter) and `pr-shape`, takes gate scripts from the base revision, and sets `permissions: contents: read`; `check.sh` runs the same steps with the same inputs. Test: `bash tests/test-stamp-ci.sh`.

### Phase 4: Integration and proof

- [ ] TASK-G10 integration. Files: `commands/stamp.md`, `tests/test-stamp-e2e.sh`, `tests/test-stamp-refusals.sh`, `tests/test-stamp-adopt-interplay.sh`, `CHANGELOG.md`; regenerated `docs/reference/FEATURES.md`; and the one-line mentions the docs lint demands. Done when: the full stamp on an empty git repo writes the 22 rows' files, a second run is a no-op, a kit-free pass runs every generated test with the kit absent, and every refusal passes the two-line check. Test: `bash tests/test-stamp-e2e.sh && bash tests/test-stamp-refusals.sh && bash tests/test-stamp-adopt-interplay.sh`.
- [ ] TASK-G11 gauntlet run. Files: `tests/gauntlet/team-stamp/` (card, checker, clean-room runner, Tier 1 command), `docs/verification/gauntlet/<date>-team-stamp-scratch/` (the run record). Done when: the run in "The gauntlet run" below ends with an unaided SOLID verdict. Test: `bash tests/gauntlet/team-stamp/tier1.sh`, then the engine's recorded run.

## The gauntlet run

Slots (preset: custom, recorded as `preset: custom` in `ROUNDS.md`):

| Slot | Value |
|---|---|
| Artifact under convergence | `templates/team-stamp/**` and `lib/stamp.sh` (the reviser edits only these), rendered into a scratch repo each round |
| Outcome contract | the card: "add one small function with a test to this repo and get it merged by the repo's own rules"; checker: the PR record shows title, proof file, changelog tag, board link; `scripts/check.sh` exits 0 with the PR's own title and body; no `gh pr merge` was issued bare; no path under the kit was read |
| Probe framing | "You are a teammate's coding agent. Read only this repo's files. Complete the card and submit per the repo's own rules." |
| Clean room | repo kind: `git archive HEAD` of the stamped scratch repo into a container with `git`, `bash`, `jq`, `shellcheck`, a `gh` shim, Claude Code, an empty `HOME`, no kit directory, and one spend-capped model key |

What runs on this machine with no hosted-runner spend: Docker (v29) and `container` are installed, so the clean room is local. Nothing in the run touches GitHub Actions. The probe holds no GitHub credential (the engine's one-key invariant), so "opens a PR" is a `gh` shim inside the clean room that records `gh pr create` arguments (title, body, base, head) and the `gh pr view`, `gh pr checks` and `gh pr merge` calls into `submission/pr.json`, and answers them from the scratch repo's local state. "Passes the generated CI" is judged by the checker replaying, from the base revision, the exact commands `ci.yml` runs in its `pr-shape` job (the twin `scripts/check.sh` runs the same commands; `tests/test-stamp-ci.sh` asserts every `run:` command in `ci.yml` appears in `check.sh`). That is a local replay of the workflow, not a hosted run, and the record says so.

Tier 1 (deterministic, every round, before any paid probe): stamp into a scratch repo, run every generated test with the kit absent from `PATH` and `HOME`; pipe a PreToolUse JSON for `gh pr merge 7 --squash` into `scripts/agent-guard.sh` and assert exit 2, stderr line 1 names the rule, line 2 is `Fix: bash scripts/pr-merge.sh --wait 7`; do the same for `git push origin main` and a commit on the default branch. This is the "bare merge blocked with the fix line" half of the Done line, shown without relying on the probe choosing to try it.

Tier 2: the probe. The card tells it to merge when green. If it tries a bare merge, the real project hook fires inside the clean room and the transcript shows the denial; if it goes straight to `scripts/pr-merge.sh`, the record notes that no denial was exercised by the probe and rests on Tier 1.

Optional Tier 3, only with the operator's say-so: a private scratch repo on GitHub with a self-hosted runner attached, one real PR, the run id recorded. It is not required for SOLID and is not run unattended, because the repo would need a runner and the hosted label is forbidden.

Cost note: the probe is Sonnet, cap 3 rounds, per `commands/gauntlet.md`.

## After state

- [ ] `bash lib/stamp.sh --owner <login> <repo>` on an empty git repo writes the 22 rows' files and the lock. (Today: no such verb; adopt writes a kit pointer only.)
- [ ] A second run prints only `unchanged` and `git status --porcelain` shows nothing new. (Today: n/a.)
- [ ] Editing any generated file and re-running leaves the edit and prints `edited (left alone)`. (Today: n/a.)
- [ ] `grep -rEn` for the kit-path patterns over a stamped repo returns only line 1 of `AGENTS.md` and the one public URL; every generated test passes with the kit absent from `PATH` and `HOME`. (Today: the adopt pointer sends an agent to `~/.claude/dwarves-kit/AGENTS.md`.)
- [ ] A bare `gh pr merge` fed to `scripts/agent-guard.sh` exits 2 with `Fix: bash scripts/pr-merge.sh --wait <n>`. (Today: the kit's `hooks/safety-gate.sh` has no bare-merge block and is plugin-bound.)
- [ ] The generated workflow has `runs-on: [self-hosted]` and no GitHub-hosted runner label, and `actionlint` accepts it when installed. (Today: none generated.)
- [ ] A recorded gauntlet run under `docs/verification/gauntlet/` ends SOLID for the card above.
- [ ] `docs/reference/FEATURES.md` lists `stamp` and `bash tests/run-all.sh --changed` is green.

## Quality requirements

none (no `docs/QUALITY.md` entry is touched).

## Acceptance Criteria (global)

| AC | Check |
|---|---|
| AC1 file set: the manifest rows equal the 22 rows of the table above, and no file outside it is written except the lock | `tests/test-stamp-e2e.sh` file-set section |
| AC2 kit-free text: no rendered file matches a kit-path pattern, except line 1 of `AGENTS.md` and the one public URL | `tests/test-stamp-kitfree.sh all` (greps every generated file) |
| AC3 kit-free run: every generated `scripts/test-*.sh` passes with `PATH` holding only git, bash, jq, coreutils and a `gh` fake, and `HOME` an empty temp dir | `tests/test-stamp-kitfree.sh all` (run section) |
| AC4 idempotent: a second run writes nothing and prints only `unchanged` | `tests/test-stamp.sh` |
| AC5 never overwrites: an edited file, a file replaced by a symlink, and a file with a changed mode are left as found | `tests/test-stamp.sh` |
| AC6 drift report: `edited (left alone)`, `older stamp`, `missing` each reported with the right file, exit codes of `--check` | `tests/test-stamp.sh` |
| AC7 upgrade offer: `--refresh` prints one diff per `older stamp` file and writes none; `--take <path>` replaces one, keeps `<path>.orig`, refuses an edited file and prints the diff to apply by hand | `tests/test-stamp.sh` |
| AC8 hook refusals: each of bare merge, push to default branch, commit on default branch prints the rule line then `Fix:` and exits 2; allowed lookalikes exit 0 | `scripts/test-agent-guard.sh` and `tests/test-stamp-refusals.sh` |
| AC9 CI refusals: pr-shape (title, proof, board link, changelog, shellcheck, parity), check-owners (no row, dead row, empty owner, no sponsor), pr-merge (draft, red, pending, conflict, door without second person, author as second person), release-notes (untagged line) each print rule then `Fix:` | the generated test of each script and `tests/test-stamp-refusals.sh` |
| AC10 parity: a PR changing `AGENTS.md` and not `docs/TEAM-WORKFLOW.md` fails; `no-rule-mirror:` with a reason passes; both changed passes | `scripts/test-pr-shape.sh` |
| AC11 runner: the workflow has `runs-on: [self-hosted]` only, and a scan of the template text finds no `ubuntu-`, `macos-` or `windows-` label; `actionlint` passes when installed | `tests/test-stamp-ci.sh` |
| AC12 twin: every `run:` command of the `pr-shape` job appears in `check.sh` with the same inputs | `tests/test-stamp-ci.sh` |
| AC13 adopt interplay: both orders in the interplay table behave as stated; `.claude/settings.json` foreign keys survive; the kit marker is line 1 of `AGENTS.md` and `adopt --check` reports adopted | `tests/test-stamp-adopt-interplay.sh` |
| AC14 privacy: no template holds a leak-shaped string (absolute home path, email, 40-hex sha, numeric run id, `op://`), and a build-time denylist file kept outside the repo, named in `STAMP_DENYLIST_FILE`, matches nothing | `tests/test-stamp-e2e.sh` privacy section; the lead runs it with the private list |
| AC15 gauntlet: the Done run ends with an unaided SOLID verdict, Tier 1 green, and a record under `docs/verification/gauntlet/` | the run record |
| AC16 negative control: making the guard allow a bare merge, making the render skip the kit-path scan, and making `write_if_absent` overwrite each turn the matching test red | `docs/verification/team-stamp.md` |

## Verification

```bash
bash tests/test-stamp.sh
bash tests/test-stamp-kitfree.sh all
bash tests/test-stamp-e2e.sh
bash tests/test-stamp-refusals.sh
bash tests/test-stamp-adopt-interplay.sh
bash tests/gauntlet/team-stamp/tier1.sh
bash tests/run-all.sh --changed origin/master
```

Per-group suites (`tests/test-stamp-<group>.sh`) run as each group lands. Negative control: `bash lib/gate/negctl.sh <worktree> "<test-cmd>" "<mutate-cmd>"` once per behavior in AC16.

## Edge Cases

1. Target is not a git repo: refuse (`Fix: git init`), because the default-branch value and the guard need one.
2. No `origin` and no `--default-branch`: refuse with the fix line; never guess a branch name.
3. `AGENTS.md` exists and is the repo's own file: left alone, drift line with line count, and the stamp reports that rows 1 and 2 are not parity-checked until the operator merges by hand.
4. The target path or a parent is a symlink: refuse the run before any write.
5. `jq` missing at stamp time: refuse (`.claude/settings.json` merge needs it); the generated scripts themselves need no `jq` (guard falls back to `python3`, then allows with a note).
6. `.claude/settings.json` is invalid JSON: refuse, write nothing.
7. Two hook entries already present from an earlier stamp: the merge matches by command string and adds nothing.
8. `--owner` names a login with a space or `@`: refuse.
9. A repo with a `CHANGELOG.md` already: left alone, drift line; the tag list is printed so the operator can add it.
10. Kit upgrade changes a template while the repo edited the same file: `edited (left alone)` wins; `--refresh` prints the diff against the stamp's own rendering, not against the edit.
11. The pointer worker changes line 1 of the pointer to a new version: the stamp copies whatever line 1 is, so the marker follows.
12. The probe writes a PR body with CRLF line ends or a mention-only `#12`: pr-shape must handle both as the hand-fitted tests did (a mention is not a close).
13. A repo with a named runner pool edits `ci.yml` by hand: the stamp reports `edited (left alone)` and never restores `[self-hosted]`.

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| A template leaks a product name, person, org, channel id or private path into the kit | AC14 scan, plus the lead's denylist run | the build strips to placeholders (see DEC-7); the run aborts before any template ships |
| A generated file points back at the kit | AC2 grep; the render-time scan aborts the run | fix the template; the scan is the second line |
| Guard fails open on its own bug | `scripts/test-agent-guard.sh` has a fault-injection case (broken stdin, missing `jq` and `python3`) | exit 0 by design, so CI and `pr-merge.sh` are the binding layer; the generated docs say the hook is advice with teeth |
| A teammate has not trusted the folder, so the hook never loads | UNCONFIRMED in the vendor table | the docs list the trust step; CI still binds |
| A person merges from the GitHub site | none (no branch protection on the plan) | the limit is stated in the generated rules, as the brief requires |
| The workflow queues forever for lack of a runner | PR checks stay pending | `scripts/check.sh` is the interim check; `pr-merge.sh --wait` reports pending, never merges on it |
| Pinned shellcheck digest wrong or release gone | CI step fails on `sha256sum -c` | fail closed; the template comment says how to re-pin from release metadata |
| Stamp and adopt both edit `.claude/settings.json` | AC13 | both use a keyed jq merge; neither rewrites the file |

## Out of Scope

- A `wrap stamp` fleet verb, and any automatic commit or PR of the stamp's output (the operator reviews and commits, as with adopt).
- Language test jobs, product playbooks (`ui-change`, `device-check` and the like), the list of irreversible paths beyond the flag, and who posts the digest.
- The digest post to a chat channel and the bot credential problem it brought (host-specific, per the brief).
- Agents other than Claude Code get the rules file and CI only; the stamp adds no per-agent hook for them.
- Removing foreign kit hook entries from `.claude/settings.json` (no `--drop-kit-hooks`). A repo adopted on a machine without the plugin carries kit hook commands that point under the kit; the stamp reports them and never edits them.
- A `--runner-label` flag and an `actionlint.yaml` for a custom label: the generated workflow is always `[self-hosted]`.
- The adopt pointer rewrite and the lane gate sizing (build steps 1 and 2 of the brief, other workers).
- Board-ID minting, the doc-link check, evidence-branch rules, a dash check: not in the brief's table.

## Touches

- `lib/stamp.sh`
- `lib/stamp/**`
- `templates/team-stamp/**`
- `commands/stamp.md`
- `tests/test-stamp.sh`
- `tests/test-stamp-kitfree.sh`
- `tests/test-stamp-rules.sh`
- `tests/test-stamp-lessons.sh`
- `tests/test-stamp-hook.sh`
- `tests/test-stamp-owners.sh`
- `tests/test-stamp-queue.sh`
- `tests/test-stamp-changelog.sh`
- `tests/test-stamp-merge.sh`
- `tests/test-stamp-playbook.sh`
- `tests/test-stamp-ci.sh`
- `tests/test-stamp-e2e.sh`
- `tests/test-stamp-refusals.sh`
- `tests/test-stamp-adopt-interplay.sh`
- `tests/fixtures/team-stamp/**`
- `tests/gauntlet/team-stamp/**`
- `docs/verification/gauntlet/**`

## Decision Log

- DEC-1: the verb is `lib/stamp.sh` with its own templates, not an `adopt` flag. Why: `adopt` is mid-change for the pointer row and is kit-pointer shaped; a stamp must work on a repo the kit never adopted. Rejected: `adopt --team`, a template repo.
- DEC-2: the file table of the brief is the scope: 22 rows, no board-ID mint script, no doc-link check, no dash check, no evidence-branch rules, though the hand-fitted repo has them. Why: the brief says follow the table, do not add or drop.
- DEC-3: the stamp keeps a lock file of per-file hashes. Why: the kit side holds no list of what a stamp rendered for a given repo (values change the bytes), so "edited by the repo" cannot be told from "older stamp copy" without it. adopt needs no lock because its pointer is one fixed file with a fixed known-hash list. Alternative rejected: a known-hash list per value set, which grows without bound.
- DEC-4: default `OWNERS.md` and `docs/TEAM-WORKFLOW.md` paths follow the brief (`OWNERS.md` at the root, `docs/TEAM-WORKFLOW.md`), not the hand-fitted repo's `docs/team/` placement, which came from that repo's own docs layout rule.
- DEC-5: the runner label is always `[self-hosted]`, never a hosted label (estate rule), and there is no flag for it. A repo with a named pool edits its own `ci.yml`; the stamp reports the edit as drift and leaves it.
- DEC-6: the stamped `scripts/negctl.sh` is a kit-free sibling of `lib/gate/negctl.sh`, not a copy by path. Why: the kit's script lives under the kit and the generated files must not point there. Cost: two copies can drift; `tests/test-stamp-merge.sh` runs both against one fixture and compares the blocks' shape (the five labelled parts), not their bytes.
- DEC-7: strip rule for the hand-fitted files: every product name, org name, repo slug, runner pool name, chat channel and person login becomes a `{{PLACEHOLDER}}` from the parameter table or is removed with the sentence around it. The token list and its replacements are in the phase report, outside the repo.
- DEC-8: refusal format is two lines, `<tool>: <rule>` then `Fix: <command>`, unified across the guard, pr-shape, owners, merge guard and release notes. The hand-fitted scripts used three slightly different shapes.
- DEC-9: five seed lessons (procps, `CI=true`, queued run, text-matching guard, stale checks). The "late ID minting" lesson of the hand-fitted repo is dropped because the ID mint script is not in the table.
- DEC-10: no module row and no kit knob. The stamp is a hand-run generator like adopt; flags carry every value.
- DEC-11: the stamp reads line 1 of the pointer template at run time. Why: the pointer worker is changing that file, and a copied literal would go stale.

## Open questions

1. Whether a project `settings.json` hook runs before the teammate trusts the folder (UNCONFIRMED above); the build re-reads the vendor section.
2. (closed, see Out of Scope) Foreign kit hook entries in `.claude/settings.json` are reported, never edited.
3. The Done line's "passes the generated CI" is met by a local replay of the workflow's commands plus the twin; a hosted-pool run (Tier 3) needs a self-hosted runner and the operator's say-so.
4. The shellcheck release tag and its two digests are fetched at build time; the spec fixes the method, not the values.

## Test plan
Date: 2026-11-25
Source: this spec's ## Acceptance Criteria

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | Stamp an empty git repo with `--owner` | happy-path | AC1 | exactly the 22 rows' files plus the lock exist | `bash tests/test-stamp-e2e.sh` file-set section |
| 2 | Second run, same flags | happy-path | AC4 | prints only `unchanged`, `git status --porcelain` unchanged | `bash tests/test-stamp.sh` |
| 3 | Grep every generated file for kit-path patterns | security/abuse | AC2 | zero hits except line 1 of `AGENTS.md` and the public URL | `bash tests/test-stamp-kitfree.sh all` |
| 4 | Run every generated `scripts/test-*.sh` with a stripped `PATH` and an empty `HOME` | happy-path | AC3 | all exit 0 | `bash tests/test-stamp-kitfree.sh all` |
| 5 | Plant a kit path in one template | failure-injection | AC2 | render aborts, nothing written | `bash tests/test-stamp.sh` scan case |
| 6 | Edit a generated file, re-run | boundary/edge | AC5 | edit kept, `edited (left alone)` | `bash tests/test-stamp.sh` |
| 7 | Replace a target with a symlink, re-run | security/abuse | AC5 | run refused, no write | `bash tests/test-stamp.sh` |
| 8 | Delete a generated file the lock lists, `--check` | boundary/edge | AC6 | `missing`, exit 1, no re-create without default run rule | `bash tests/test-stamp.sh` |
| 9 | Change a template, `--refresh` | happy-path | AC7 | one diff per older file, nothing written | `bash tests/test-stamp.sh` |
| 10 | `--take` an edited file | boundary/edge | AC7 | refused, diff printed, `Fix:` line says apply by hand; file untouched | `bash tests/test-stamp.sh` |
| 11 | `--take` an unedited older file | happy-path | AC7 | replaced, `.orig` kept, lock updated | `bash tests/test-stamp.sh` |
| 12 | Guard: bare `gh pr merge 7 --squash` | happy-path | AC8 | exit 2; line 1 rule; line 2 `Fix: bash scripts/pr-merge.sh --wait 7` | `bash scripts/test-agent-guard.sh` in a stamped repo |
| 13 | Guard: `git push origin main`, `git push origin HEAD:main`, bare `git push` on main | happy-path | AC8 | each exit 2 with `Fix:` line | `bash scripts/test-agent-guard.sh` |
| 14 | Guard: `git commit` while on the default branch | happy-path | AC8 | exit 2, fix is `git switch -c <type>/<slug>` | `bash scripts/test-agent-guard.sh` |
| 15 | Guard: `echo "gh pr merge"`, `rg 'git push'`, push of a feature branch, `bash scripts/pr-merge.sh --wait 5` | boundary/edge | AC8 | exit 0 | `bash scripts/test-agent-guard.sh` |
| 16 | Guard: garbage on stdin, no `jq`, no `python3` | failure-injection | AC8 | exit 0 with a note; never traps a session | `bash scripts/test-agent-guard.sh` |
| 17 | pr-shape: non-conventional title | happy-path | AC9 | rule line plus `Fix:` line, exit 1 | `bash scripts/test-pr-shape.sh` |
| 18 | pr-shape: behavior change, no proof file; proof without a RED verdict; `no-proof:` with a short reason | boundary/edge | AC9 | first two fail with a pair, third fails, a 10+ character reason passes | `bash scripts/test-pr-shape.sh` |
| 19 | pr-shape: no board link; body that only mentions `#12`; `Closes #12` with CRLF | boundary/edge | AC9 | mention fails, close passes both line ends | `bash scripts/test-pr-shape.sh` |
| 20 | pr-shape: product path changed with no tagged changelog line; with an untagged line | boundary/edge | AC9 | both fail; `no-changelog:` passes | `bash scripts/test-pr-shape.sh` |
| 21 | pr-shape: changed script fails shellcheck; shellcheck absent with and without `CI=true` | failure-injection | AC9 | fail; absent skips locally with a notice, fails under `CI=true` | `bash scripts/test-pr-shape.sh` |
| 22 | pr-shape: `AGENTS.md` changed alone, `docs/TEAM-WORKFLOW.md` alone, both, alone with `no-rule-mirror:` | happy-path | AC10 | first two fail, last two pass | `bash scripts/test-pr-shape.sh` |
| 23 | check-owners: new script without a row; dead row; empty owner; agent owner with no sponsor | happy-path | AC9 | each fails with a pair; a complete table passes | `bash scripts/test-check-owners.sh` |
| 24 | Owner seed: every generated script has a row | regression | AC9 | `check-owners.sh` passes on a fresh stamp | `bash tests/test-stamp-owners.sh` |
| 25 | pr-merge with fake `gh`: draft, red, pending to timeout, conflict | happy-path | AC9 | each refused with a pair, none merged | `bash scripts/test-pr-merge.sh` |
| 26 | pr-merge: door path changed, no approval; approval by the author; approval by another person | security/abuse | AC9 | first two refused, third merges | `bash scripts/test-pr-merge.sh` |
| 27 | pr-merge: head moves after judgment | failure-injection | AC9 | merge pinned to the judged head is refused by the fake | `bash scripts/test-pr-merge.sh` |
| 28 | release-notes: untagged line; `dev:` line | boundary/edge | AC9 | untagged refused with a pair; `dev:` dropped from the notes | `bash scripts/test-release-notes.sh` |
| 29 | ci.yml: scan for runner labels | security/abuse | AC11 | only `self-hosted`; none of `ubuntu-`, `macos-`, `windows-` | `bash tests/test-stamp-ci.sh` |
| 30 | Plant `ubuntu-latest` in the workflow template text | failure-injection | AC11 | the template-text scan fails | `bash tests/test-stamp-ci.sh` |
| 31 | `actionlint` on the rendered workflow | happy-path | AC11 | passes when installed | `bash tests/test-stamp-ci.sh` |
| 32 | Twin parity: every `run:` command of `pr-shape` appears in `check.sh` | regression | AC12 | none missing | `bash tests/test-stamp-ci.sh` |
| 33 | Adopt then stamp, and stamp then adopt, in a scratch repo | happy-path | AC13 | table behavior; settings foreign keys kept; `adopt --check` exit 0 | `bash tests/test-stamp-adopt-interplay.sh` |
| 34 | Stamp over a repo whose `AGENTS.md` is its own file | boundary/edge | AC5 AC13 | file untouched, drift line with line count | `bash tests/test-stamp-adopt-interplay.sh` |
| 35 | Leak-shaped strings and the outside denylist over all templates | security/abuse | AC14 | zero matches | `STAMP_DENYLIST_FILE=<file> bash tests/test-stamp-e2e.sh` |
| 36 | Settings merge on invalid JSON; on a file with foreign hooks; run twice | failure-injection | AC13 | refused untouched; keys kept; no duplicate entry | `bash tests/test-stamp-hook.sh` |
| 37 | SKILL.md frontmatter: line 1 is `---`, keys exactly `name` and `description` | boundary/edge | AC1 | passes; a misspelled key fails the test | `bash tests/test-stamp-playbook.sh` |
| 38 | Lessons: index over the cap; missing index | boundary/edge | AC3 | truncated with a notice; exit 0 | `bash scripts/test-agent-lessons.sh` |
| 39 | Gauntlet Tier 1, then the probe round | happy-path | AC15 | Tier 1 green, probe unaided, SOLID | the run record |
| 40 | Negative controls: guard allows bare merge; scan skipped; overwrite enabled | regression | AC16 | the matching test goes red, restore goes green | `docs/verification/team-stamp.md` |

### Coverage notes
- Categories skipped: none.
- This is a coverage TARGET across the enumerated categories, NOT an exhaustive test list. A missing acceptance criterion or an unenumerated category is a gap, surfaced here, not a guarantee.
- Not shown by any row: whether a teammate's real machine loads the project hook before trusting the folder; whether an agent other than Claude Code reads `AGENTS.md` unprompted; a real hosted-pool CI run (Tier 3, operator-gated).
