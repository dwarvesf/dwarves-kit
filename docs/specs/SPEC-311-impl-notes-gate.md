# Spec: the full lane's ship gate requires an implementation-notes file

Generated: 2026-09-24
Status: VALIDATED (branch `feat/impl-notes-gate`), revised after Validate
Lane: full
Type: spec-feature
File: `docs/specs/SPEC-311-impl-notes-gate.md`
References: `hooks/ship-gate.sh` (the lane-gate block at its end); `lib/gate/gate-ledger.sh` (`check`); `lib/goal/mega-merge.sh` (`gate`); `lib/telemetry/lane-telemetry.sh` (`_shipped_incomplete`); `lib/gate/proof-table-gen.py`; `commands/execute.md` (implementation-notes rule); `commands/wrap.md` step 10; `docs/WORKFLOW.md` "Gate ledger and ship enforcement"; `lib/pitch.sh` (the slug to notes-file mapping).

## Problem

A full-lane change can ship with no implementation-notes file. On 2026-09-24 a wrap step 10 worker finished SPEC-310 (PR #754). `bash lib/gate/gate-ledger.sh check full wrap-follow-through` exited 0, and `docs/implementation-notes/wrap-follow-through.md` did not exist. The lead wrote the file by hand before merge.

The rule to keep notes reaches an agent two ways: `commands/execute.md` and `commands/next.md` prose, and a global instruction that a UserPromptSubmit hook injects. The hook fires on the main session's prompts only. A subagent never sees it, so every subagent-run full lane skips the notes unless its brief repeats the rule. Nothing checks the result.

## Solution

### Approaches considered

1. **Inside `gate-ledger.sh check`.** One function, and every caller would inherit the rule. But `check` reads only the run ledger, keyed by rid, with no repo root. Three of its four callers cannot give it the pushed repo: `lane-telemetry.sh` loops over every historical rid from any cwd, `proof-table-gen.py` renders history, and `mega-merge.sh gate` decides on a rid. A file check there would either guess the root from the cwd (wrong repo, or every past full run flagged incomplete) or check today's HEAD against a past run.
2. **In `hooks/ship-gate.sh`, beside the ledger check.** The hook already resolves `ROOT`, `SLUG`, `SPEC` and `LANE` for the push, and it is the full lane's one hard gate. Every scripted path that lands a full-lane branch pushes through it: the operator's push, `/kit:ship`, and wrap step 10's lead push (`cd <wt> && git push`). PHILOSOPHY N3 names the ship-gate as the place that owns blocking.
3. **A worker-brief rule only.** Prose in `commands/wrap.md` step 10. It fixes the known path but checks nothing.
4. **A SubagentStart hook that injects the notes rule.** Reaches every subagent, not only step 10 workers. It is still an instruction, not a check, and the kit wires no SubagentStart hook today, so it adds a new hook surface for one rule.

### Chosen approach + why

Approach 2 as the backstop, plus approach 3 so the step 10 worker writes the file before the lead's push instead of after a refusal. The hook is the only enforcement point that knows which repo and branch ship. `gate-ledger.sh check` keeps its contract: ledger in, gaps out.

## Design

Chosen: approach 2 plus the step 10 worker-contract clause.

### Design record

**Rule.** When the ship-gate's lane arm runs (a spec `docs/specs/SPEC-*-<slug>.md` exists, its `Lane:` header parses, `lane_gates` is on) and the lane is `full`, one of two files must exist in the `HEAD` tree of the pushed repo, read with `git -C "$ROOT" show "HEAD:<path>"`:
- `docs/implementation-notes/<slug>.md`, where `<slug>` is the branch name with its `type/` prefix stripped (the hook's existing `SLUG`);
- `docs/implementation-notes/<spec-basename>.md`, the spec's own file name (`SPEC-NNN-<slug>.md`). 36 of the kit's 162 notes use this form, SPEC-309's included.

The file passes when it holds at least one non-blank line that is not a `# ` level-one title. Entries (`## ...`), decision tables, bullet lists and prose all count.

**Valid zero-deviation note.** A title plus `No deviations; matches the spec verbatim` passes. That is the line `commands/execute.md` prescribes. A title-only file fails: it records nothing.

**Committed, not working tree.** A push ships commits, so an uncommitted notes file does not count.

**Block or warn.** In an adopted repo (`docs/verification/README.md` present, the marker the lane-less spec check already uses) a notes gap blocks: it joins the ledger gaps in one BLOCKED message, one exit 2, one `BLOCKED | ship-gate` log line, and the OUTCOME marker records `caught=true`. In a repo without the marker the hook prints a `[advisory]` line and does not block, keeping the hook's fail-open contract for repos that never opted in.

**Logged override.** `bash lib/gate/gate-ledger.sh override <slug> impl-notes "<reason>"` clears the gap for that run. `override()` already accepts any phase name, so `gate-ledger.sh` does not change; the hook reads the run ledger for a `| GATE | impl-notes | override |` line. This keeps the "Detect, don't dictate" condition that every ship block carries a logged override. `[gate] lane_gates = false` still switches the whole lane arm off.

**Scope.** Lane `full` only, root `docs/specs/` specs only (the lane arm's existing reach). Other lanes, spec-less pushes and co-located `tools/*/docs/specs/` specs are never checked.

### Extensibility & boundaries

`gate-ledger.sh`, `lane-telemetry.sh` and `proof-table-gen.py` do not change. `mega-merge.sh gate` keeps calling `check` only; its comment that it "can never drift looser than the ship-gate" becomes false and is corrected to say it mirrors the ledger arm. The notes naming follows `lib/pitch.sh` and `commands/execute.md`.

## Picture

```
push / gh pr create (feature branch)
        |
        v
ship-gate.sh: ROOT, SLUG, SPEC, LANE
        |
        +--> gate-ledger.sh check <lane> <slug> --> ledger gaps
        |
        +--> lane == full and no "impl-notes override" in the ledger ?
        |       yes: git -C ROOT show HEAD:docs/implementation-notes/{<slug>,<spec-basename>}.md
        |            any non-blank non-title line ? no --> MISSING-NOTES gap
        |            (repo without the proof marker: [advisory], no gap)
        v
any gap --> BLOCKED, exit 2, OUTCOME caught=true
none    --> exit 0,          OUTCOME caught=false
```

## After state

In an adopted repo, a full-lane branch whose root spec has no committed notes file cannot be pushed through the ship-gate without a logged override. A no-deviation change passes with one line. The step 10 full-lane worker contract names the notes file. `docs/WORKFLOW.md` and `commands/execute.md` state the rule, and `commands/execute.md` no longer tells a worker to leave a title-only file.

## Task Breakdown

| Task | Files | Depends on |
|---|---|---|
| T1: notes check in the lane arm, new suite | `hooks/ship-gate.sh`, `tests/test-ship-gate-impl-notes.sh` | none |
| T1b: add notes to full-lane pass-path fixtures | every `tests/test-*.sh` suite that pushes a full-lane spec expecting exit 0 and turns red after T1 | T1 |
| T2: docs and comments | `docs/WORKFLOW.md`, `commands/execute.md`, `commands/wrap.md` step 10, `lib/goal/mega-merge.sh` comment, `docs/FEATURES.md` regen | T1 |
| T3: this change's own notes and proof | `docs/implementation-notes/impl-notes-gate.md`, `docs/verification/impl-notes-gate.md` | T1 |

## Acceptance Criteria (global)

- AC1: a full-lane push with every required gate recorded and no notes file exits 2, and stderr names `MISSING-NOTES` and the path.
- AC2: the same push with a committed `<slug>.md` holding a `## ` entry exits 0; so does one holding only a decision table.
- AC3: a committed notes file holding only a title and `No deviations; matches the spec verbatim` exits 0.
- AC4: a title-only notes file exits 2.
- AC5: a notes file present in the working tree but not committed exits 2.
- AC6: a `normal`-lane push with no notes file exits 0.
- AC7: with a notes gap and a ledger gap together, one BLOCKED message lists both.
- AC8: `lib/gate/gate-ledger.sh` is byte-identical to `origin/master`.
- AC9: every existing ship-gate suite stays green (T1b edits their fixtures only).
- AC10: `docs/WORKFLOW.md`, `commands/execute.md` and `commands/wrap.md` step 10 name the rule; `commands/execute.md` no longer says "header only" or "do not let it block your commit".
- AC11: a committed `SPEC-NNN-<slug>.md` notes file satisfies the rule.
- AC12: `gate-ledger.sh override <slug> impl-notes "<reason>"` clears the gap, exit 0.
- AC13: in a repo without `docs/verification/README.md`, a missing notes file prints `[advisory]` and exits 0.
- AC14: a push written `cd <repo> && git push` from another cwd checks the notes in `<repo>`.

## Test plan

| # | Case | Category | Covers (AC) | Expected | Proof |
|---|------|----------|-------------|----------|-------|
| 1 | full lane, gates recorded, no notes | failure-injection | AC1 | exit 2, MISSING-NOTES | new suite |
| 2 | full lane, notes with `## ` entry | happy-path | AC2 | exit 0 | new suite |
| 3 | full lane, zero-deviation line only | happy-path | AC3 | exit 0 | new suite |
| 4 | full lane, header-only notes | boundary | AC4 | exit 2 | new suite |
| 5 | full lane, notes uncommitted | boundary | AC5 | exit 2 | new suite |
| 6 | normal lane, no notes | regression | AC6 | exit 0 | new suite |
| 7 | full lane, missing review gate and no notes | failure-injection | AC7 | exit 2, both gaps | new suite |
| 8 | byte diff of gate-ledger.sh | regression | AC8 | no diff | new suite |
| 9 | existing ship-gate suites | regression | AC9 | green | suite loop |
| 10 | grep the three docs | doc check | AC10 | match | new suite |
| 11 | notes named `SPEC-001-<slug>.md` | happy-path | AC11 | exit 0 | new suite |
| 12 | no notes, override recorded | happy-path | AC12 | exit 0 | new suite |
| 13 | no marker, no notes | boundary | AC13 | exit 0 + advisory | new suite |
| 14 | push via `cd <repo> &&` from a foreign cwd | boundary | AC14 | exit 2 without notes | new suite |

## Verification

```
bash tests/test-ship-gate-impl-notes.sh
for t in $(rg -l 'ship-gate' tests/test-*.sh); do bash "$t" >/dev/null 2>&1 && echo "ok $t" || echo "FAIL $t"; done
bash lib/gate/negctl.sh "$PWD" "bash tests/test-ship-gate-impl-notes.sh" "git show origin/master:hooks/ship-gate.sh > hooks/ship-gate.sh"
```

Proof of done: `docs/verification/impl-notes-gate.md`.

## Failure modes

| Failure | Effect | Handling |
|---|---|---|
| an adopted repo runs full-lane specs without the notes habit | its full-lane push blocks | the message names both accepted paths, the one-line zero-deviation fix and the override |
| notes file named for neither accepted form | block | the message prints both expected paths |
| push written `git -C <wt> push` from the main checkout | the hook resolves the session repo, finds no spec, exits 0 | known gap of the hook's `cd`-only root parse, shared by every lane gate; wrap step 10 uses `cd <wt> &&` |
| push of another ref (`git push origin feat/other`) | checks the current HEAD's notes | known gap shared by every lane gate |
| the engage regex matches `git push` inside another command's text | a read-only command can be blocked | pre-existing false trip; separate change |

## Edge Cases

- A re-push of a branch whose notes file already sits in `HEAD`: passes.
- A notes file whose only mention is prose such as "there were no deviations": passes; it is a recorded statement.

## Out of Scope

- Checking notes quality beyond one non-title line.
- Requiring notes for `normal` or `bug` lanes, spec-less runs whose ledger says `lane=full`, or co-located `tools/*/docs/specs/` specs.
- Changing `gate-ledger.sh check`, or making `mega-merge.sh gate` read repo files.
- A repo-wide test that every historical full-lane spec has notes (older specs predate the habit).
- Aligning `lib/pitch.sh`'s notes parsing with this rule.
- Fixing the hook's `git -C` root parse or its engage-regex false trip.

## Decision Log

- Enforcement point is the ship-gate, not `gate-ledger.sh check`: `check` has no repo root and three of its four callers cannot give one.
- The zero-deviation line counts, so an empty delta never forces invented content.
- The file must be committed: a push ships commits.
- Revised after Validate (two fresh reviewer agents, six lenses): accept the `SPEC-NNN-<slug>.md` name; pass any non-title line instead of `## ` or "no deviations" (6 existing notes, SPEC-309's included, use tables); add the logged `impl-notes` override ("Detect, don't dictate" needs one); advisory, not block, outside adopted repos; `git -C "$ROOT"`; fix `commands/execute.md`'s "header only" and "do not let it block" clauses; correct the `mega-merge.sh` comment; list the fixture edits as T1b; SubagentStart injection added as approach 4. Design record: pass.
