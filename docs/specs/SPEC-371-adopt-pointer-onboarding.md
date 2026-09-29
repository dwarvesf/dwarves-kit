# Spec: adopt writes a small pointer AGENTS.md, and the first run teaches two ideas
Generated: 2026-09-29
Status: DRAFT
Lane: full (kit-machinery: `lib/adopt.sh` writes into every consumer repo; from `bash lib/classify/lane-classify.sh explain`, flag `kit-machinery`)
References: `lib/adopt.sh:203-207` (the copy this spec replaces); `tests/test-adopt.sh:37-41` and `:86-96` (the never-overwrite tests this spec changes); `docs/research/2026-09-29-openrig-absorption.md:136-141` (design D6); `docs/verification/gauntlet/2026-09-01-onboarding-campaign/J2/` (the baseline run: install, adopt, ship one tiny change)

## Problem

`/kit:adopt` copies the kit's own `AGENTS.md` into the target repo once and never touches it again (`lib/adopt.sh:203-207`, header comment `lib/adopt.sh:7-8`, `--refresh` note `lib/adopt.sh:15-16`). The copy is 18033 bytes and 229 lines (`wc -c AGENTS.md`), about 4.5k tokens, loaded every session because the adopted `CLAUDE.md` block imports `@AGENTS.md` (`lib/adopt.sh:197`). Three costs:

- Every session in an adopted repo pays about 4.5k tokens, most of it kit-internal detail (goal composition, subsystem modules) that a normal task never needs.
- The copy goes stale. No code path updates it.
- The first-run tour (`commands/onboard.md:227-243`) lists five stages, and the path to a first normal-lane ship asks for far more than that (research note `docs/research/2026-09-29-openrig-absorption.md:89-98`: about 18 concepts and 10 commands).

### Premise check

| Claim in the design note | Checked | Result |
|---|---|---|
| Copy costs about 4.5k tokens per session | `wc -c AGENTS.md` = 18033 bytes; the `@AGENTS.md` import is at `lib/adopt.sh:197` | Holds (bytes/4). Exact token count is not measured; the measurement plan below does it. |
| "trading's copy is 322 lines behind" | `/usr/bin/diff` of `tieubao/trading/AGENTS.md` against the kit `AGENTS.md`: 188 lines only in the kit, 134 only in trading, total 322 | Wrong reading. 322 is the sum of changed lines. Trading's file starts `# Trading` and is repo-authored, not a stale kit copy. So the real number of stale kit copies in the wild is unknown, and migration must treat "not a kit copy" as the common case. |
| Claude can load the full contract through an import | Adopted `CLAUDE.md` already uses `@AGENTS.md` (`lib/adopt.sh:197`, `tests/test-adopt.sh:44`). Every install mode keeps `~/.claude/dwarves-kit` pointing at the install (`lib/adopt.sh:46-49`) | An import of an installed path is possible, but it would load the same 18KB again and save nothing. See Design. |
| Non-Claude agents follow a `@import` | Not testable here. The repo has no Codex or Devin harness run of an import | Treated as false. The small file must be self-sufficient. |
| Plugin-only machines have the hook path | `commands/onboard.md:207-213`: on plugin-only machines the adopt-wired per-repo hooks do not fire | So a SessionStart hook cannot be the loader. |
| Drift figure exists as a number adopt can produce | A line-count drift is one `diff | grep -c '^[<>]'` | Yes, and it reproduces the 322 above. |

## Solution

### Approaches considered

| | A. Small repo file, full contract on demand | B. Repo file is gone; CLAUDE.md imports the installed contract | C. Small file plus a SessionStart hook that injects the full contract |
|---|---|---|---|
| Codex, Devin, Cursor | Read the small file, get the core rules | Read nothing useful (no repo `AGENTS.md`, or an import they cannot follow) | Small file only; the hook never runs for them |
| Claude tokens per session | about 0.3k to 0.5k, plus the full contract only when the agent reads it | 4.5k, no saving | 4.5k, no saving |
| Drift | Ends: the small file has no version-bound detail | Ends | Ends |
| No kit on the machine | File still gives rules and an install line | Dangling import; agent gets nothing | Hook absent; small file remains |
| Plugin-only machine | Works | Works | Hook path does not fire (`commands/onboard.md:207-213`) |
| Extra parts | none | edits CLAUDE.md block, removes a file | a new hook, a wiring entry |

### Chosen approach + why

A. B fails the non-Claude agents and saves no tokens. C saves no tokens and adds a moving part that is dead on plugin machines. A keeps the current `@AGENTS.md` import unchanged (`lib/adopt.sh:197`), so a repo that edited its own `AGENTS.md` still loads it. The full contract is one read away, and the agent already reads it at task start: the small file tells it to, and `commands/start.md` is the first command of every session.

The cost of A, stated plainly: an agent that skips the read works from about six rules, not 229 lines. That is the intended trade (the design note's lesson: "the default, not the size", `docs/research/2026-09-29-openrig-absorption.md:96-98`). The measurement below decides whether the trade holds.

### The small file

Template lives at `lib/adopt/AGENTS.pointer.md`. Target 1KB, hard cap 1200 bytes. First line is a marker `<!-- kit:agents-pointer v1 -->`. Content, in this order:

1. One line: this repo uses dwarves-kit; the full contract is `~/.claude/dwarves-kit/AGENTS.md`; read it before the first task.
2. The rules a non-Claude agent needs with no other file: size the work as `tiny`, `normal` or `full` (with the classify command); a change that alters behavior or state needs a recorded proof of done under `docs/verification/` before push; never push to main, use a branch and a PR; stop and ask a human before an architecture change, weakening a test or guardrail, moving to a lighter lane, or touching secrets or access (the "Pause if" list, `AGENTS.md:171-182`, cut to one line).
3. One line for a machine without the kit: rules 2 to 4 still hold, nothing enforces them, and the install command.

Enforcement stays Claude-only, as `AGENTS.md:8-13` already says; the small file repeats that in one clause and does not claim more.

### Migration (kit AGENTS.md copy to pointer)

adopt decides by hash, not by size or date. The hash list `lib/adopt/agents-known.sha256` holds the sha256 of every version of `AGENTS.md` ever committed (28 commits today: `git log --format=%h -- AGENTS.md`) plus each released pointer version. A test keeps this list complete.

| State of the target `AGENTS.md` | Plain adopt | `--refresh` |
|---|---|---|
| absent | write the pointer | write the pointer |
| hash is in the known list (unmodified kit copy or older pointer) | leave it; print `old kit copy, N lines; --refresh swaps it for the pointer` | replace with the current pointer, atomically (tmp + mv, as `lib/adopt.sh:213`) |
| hash is not in the list (edited locally, or repo-authored like trading's) | leave it; print `AGENTS.md differs from the kit contract by N lines (left alone)` | same: leave it, print the same line |
| `--single-source` mode | skip all of this (the file is the operator's folded `CLAUDE.md`, `lib/adopt.sh:139-172`) | skip |

`N` is `diff <installed AGENTS.md> <target AGENTS.md> | grep -c '^[<>]'`. A local file is never rewritten, never merged, and never deleted.

### First-run tour

`commands/onboard.md` section G (`:227-243`) becomes two ideas plus a menu:

- **Lane**: the work is sized `tiny`, `normal` or `full`, so small changes stay light.
- **Proof of done**: a change that alters behavior is not done until a recorded run shows it works; the ship-gate checks this at push.
- **Menu (opt-in, one line each, none required)**: `/kit:spec`, `/kit:execute`, `/kit:review`, `/kit:wrap`, `/kit:dispatch`, `/kit:mega`, `/kit:observe`, `/kit:retro`.

It still ends on "run `/kit:start`". Sections A to F of onboard (mode detection, modules, knobs) are not touched: they gate choices the user must make and belong to a separate trim.

### Starter templates per lane (dependency, not in this spec)

A per-lane starter needs the lane definitions as data, which SPEC-368 (lanes-as-data) owns. This spec does not wait for it and does not write any starter. When SPEC-368 lands, a starter is one more file per lane referenced from the menu. Until then the menu names commands only.

### Measurement

The baseline is the existing campaign row J2 (install, adopt, ship one tiny change to a submitted `PR.md`; `docs/verification/gauntlet/2026-09-01-onboarding-campaign/J2/CARD.md:1-12`, checker `J2/checker-output.txt`). Its transcript `J2/transcript.jsonl` yields, with `jq`:

| Metric | Baseline from the committed J2 transcript |
|---|---|
| Turns (`type == "turn_start"`) | 47 |
| Tokens (sum of assistant `message_end` `usage.totalTokens`) | 2,971,254 (cache reads dominate) |
| Output tokens | 16,137 |

The new campaign pass re-runs J2 with the same probe and fixture after the change and reports the same three numbers side by side. One run per side is a single sample, not a benchmark; the spec claims direction only, and the result is recorded even if it is worse.

## Task Breakdown

### Phase 1: The file and the migration
- [ ] TASK-A: add `lib/adopt/AGENTS.pointer.md` (size cap 1200 bytes, marker first line, names `~/.claude/dwarves-kit/AGENTS.md`); acceptance: AC-1, AC-2.
- [ ] TASK-B: add `lib/adopt/agents-known.sha256` and `lib/adopt/known-hashes.sh` (regenerate the list from git history plus the current template); acceptance: AC-5.
- [ ] TASK-C: change `lib/adopt.sh` step 1 (`:203-207`) to write the pointer, and add the hash decision table above; update the header comment (`:7-8`, `:15-16`); acceptance: AC-1 to AC-4.

### Phase 2: Tests and docs
- [ ] TASK-D: rewrite `tests/test-adopt.sh:37-41` and `:86-96` for the new rule (a local file survives; a known copy is replaced only on `--refresh`); add the cases in the Test plan; acceptance: AC-3, AC-4, AC-5.
- [ ] TASK-E: update `commands/adopt.md` ("What adoption installs", first bullet) and replace `commands/onboard.md` section G; acceptance: AC-6.

### Phase 3: Measure
- [ ] TASK-F: add `lib/adopt/onboarding-cost.sh <transcript.jsonl>` printing turns and tokens; run the J2 pass after the change; write `docs/verification/onboarding-pointer/RESULT.md` with both columns; acceptance: AC-7.

## After state
- [ ] A fresh adopt writes an `AGENTS.md` of 1200 bytes or less that names the installed contract path. (Today: 18033 bytes, a full copy.)
- [ ] A locally edited `AGENTS.md` is byte-identical after `--refresh` and adopt prints its drift in lines. (Today: never touched, never reported.)
- [ ] An unmodified old kit copy becomes the pointer on `--refresh`. (Today: stays forever.)
- [ ] The tour teaches two ideas and lists the rest as a menu. (Today: five stages.)
- [ ] A recorded before and after exists for turns and tokens on J2. (Today: baseline only, in the transcript.)

## Acceptance Criteria (global)

| ID | Criterion | Verification command |
|---|---|---|
| AC-1 | Fresh adopt writes a pointer at or under the cap | `t=$(mktemp -d) && bash lib/adopt.sh "$t" >/dev/null && [ "$(wc -c < "$t/AGENTS.md")" -le 1200 ]` |
| AC-2 | The pointer names the installed contract and carries the marker | `t=$(mktemp -d) && bash lib/adopt.sh "$t" >/dev/null && grep -qF '~/.claude/dwarves-kit/AGENTS.md' "$t/AGENTS.md" && head -1 "$t/AGENTS.md" \| grep -qF 'kit:agents-pointer'` |
| AC-3 | A locally edited `AGENTS.md` survives `--refresh` byte for byte | `bash tests/test-adopt.sh` (case "edited AGENTS.md survives --refresh") |
| AC-4 | Drift is reported with a line count and the file is not touched | `bash tests/test-adopt.sh` (case "drift line printed with N") |
| AC-5 | An unmodified old kit copy is replaced on `--refresh`, and every historical hash is in the list | `bash tests/test-adopt.sh` (cases "old copy refreshed" and "known list complete against git log") |
| AC-6 | Docs and tour match the new behavior | `bash tests/test-meta.sh` |
| AC-7 | A before and after result exists, with turns and tokens for both | `test -f docs/verification/onboarding-pointer/RESULT.md && grep -c 'turns' docs/verification/onboarding-pointer/RESULT.md` |
| AC-8 | No regression | `bash tests/test-adopt.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh` |

## Verification
`bash tests/test-adopt.sh && bash tests/test-meta.sh && bash tests/test-hooks.sh`, then the AC-1, AC-2 and AC-7 commands above.

## Test plan

Negative controls are the point: each states the mutation and the test that goes red.

| # | Case | Setup | Expect | Negative control (mutation, then red test) |
|---|---|---|---|---|
| T1 | Fresh adopt under the cap | empty dir, `git init`, run adopt | `AGENTS.md` at or under 1200 bytes, names the pointer target | Mutate: make adopt `cp` the full `AGENTS.md` again. AC-1 goes red on size. |
| T2 | Edited file survives `--refresh` | adopt, append `LOCAL-EDIT-SENTINEL` to `AGENTS.md`, `cmp` a copy, run `--refresh` | `cmp` clean; sentinel present | Mutate: remove the hash check so refresh always rewrites. T2 goes red. |
| T3 | Repo-authored file survives | write `# Trading` style file first, run adopt and `--refresh` | file byte-identical; the drift line names a nonzero N | Mutate: treat unknown hash as "replace". T3 goes red. |
| T4 | Old kit copy is replaced on `--refresh` only | seed target with a historical copy (`git show <sha>:AGENTS.md`); plain adopt, then `--refresh` | plain: unchanged plus the "old kit copy" line; refresh: equals the pointer | Mutate: replace on plain adopt too. The "unchanged after plain adopt" assert goes red. |
| T5 | Known list is complete | for each commit in `git log --format=%H -- AGENTS.md`, hash the blob | every hash present in `agents-known.sha256` | Mutate: delete one line from the list. T5 goes red. |
| T6 | `--dry-run` writes nothing | as `tests/test-adopt.sh:53` | no files | existing test stays green |
| T7 | `--single-source` untouched | as `tests/test-adopt.sh:278-302` | no pointer written, no drift line | Mutate: run the migration in single-source mode. The existing byte-compare goes red. |
| T8 | Missing installed contract | run adopt with `KIT_ROOT` set to an empty dir and `SRC_ROOT` file present | still writes the pointer (it is a template, not a copy) | Mutate: make the pointer read `$src_agents`. T8 goes red. |
| T9 | Cost script | run `onboarding-cost.sh` on the committed J2 transcript | prints `turns 47` and `tokens 2971254` | Mutate: count `agent_start`. The exact-number assert goes red. |

The two required controls from the brief are T2 (locally edited copy survives untouched) and T1/AC-2 (fresh adopt is under the cap and still names the target).

## Edge Cases
1. Target has no `AGENTS.md` but has a `CLAUDE.md`: pointer is written, the existing block append path is unchanged (`lib/adopt.sh:222-226`).
2. Known-copy file with CRLF or a trailing newline change: hash differs, so it counts as edited and is left alone. Safe direction.
3. The installed contract is not at `~/.claude/dwarves-kit/AGENTS.md` (odd install): the pointer names the portable `KIT_REF` form (`lib/adopt.sh:50`), never an expanded home path (`lib/adopt.sh:44-49`).
4. `--check` (`lib/adopt.sh:127-129`) still keys on file presence, not content: a pointer file and an old copy both read as adopted.
5. A later kit release changes the pointer: the old pointer hash goes into the known list in the same commit, so `--refresh` upgrades it and a hand-edited pointer stays.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Agent skips the full-contract read and works from six rules | J2 result worse (more turns or a red checker) | The measurement gates the claim; revert is one commit (restore the copy at `lib/adopt.sh:205`). |
| Known-hash list misses a version, so a stale copy reads as "edited" | Drift line printed on a file that is really an old copy; T5 catches it in CI | Regenerate with `known-hashes.sh`. Failure direction is safe (file left alone). |
| Pointer promises enforcement a non-Claude agent lacks | Review of the file text | The file repeats the advisory-only boundary (`AGENTS.md:8-13`) in one clause. |

## Out of Scope
- Starter templates per lane (needs SPEC-368; named above, not built here).
- Trimming `commands/onboard.md` sections A to F (module and knob choices).
- Editing the kit's own `AGENTS.md` content or the `@AGENTS.md` block in adopted `CLAUDE.md` (`lib/adopt.sh:194-201`).
- Any hook change; `commands/execute.md` (SPEC-369); `lib/classify/**`, `kit.toml` lanes, `WORKFLOW.md` (SPEC-368).
- A multi-sample benchmark. One J2 pair is direction only.

## Touches
`lib/adopt.sh`, `tests/test-adopt.sh`, `commands/adopt.md` and `commands/onboard.md` are single files, which the dispatch gate cannot prove disjoint by prefix, so it serializes them against any sibling that lists them. No sibling spec lists them.
- lib/adopt/**
- docs/verification/onboarding-pointer/**

## Decision Log
- DEC-A: pick approach A (small file, full contract on demand), because B saves no tokens and loses non-Claude agents, and C saves no tokens and is dead on plugin machines; rejected B and C.
- DEC-B: hash list, not size or mtime, decides "unmodified", because size and mtime both misfire on a checkout; rejected size and date heuristics.
- DEC-C: leave the `@AGENTS.md` block in `CLAUDE.md` unchanged, so an edited local file still loads; rejected importing the installed path.
- DEC-D: do not chase the "322 lines behind" figure: it measures a repo-authored file, so the fix is a rule for "not a kit copy", not a sync job.

## Open questions
1. Does the small file plus on-demand read cost fewer turns and tokens on J2, or does the missing contract cause detours? Only the measurement answers it.
2. Is 1200 bytes the right cap once the rules are written, or 1000? Decide when the template is drafted; the AC follows the number.
3. Should `/kit:start` also print the drift line, so a repo-authored `AGENTS.md` stays visible after adopt day? Not needed for this spec; ask the operator.
