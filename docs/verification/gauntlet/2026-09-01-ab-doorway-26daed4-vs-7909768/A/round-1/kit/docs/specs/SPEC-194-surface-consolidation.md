# Spec: surface consolidation (harness-loop sub-goal 04)

Generated: 2026-07-12
Status: VALIDATED
Lane: full (per `bash bin/classify lane classify`; the diff edits `lib/` + `hooks`-adjacent
enforcement surfaces (install.sh, bin/ entrypoints) and every consumer's entry grammar --
kit-machinery gate).

## Problem

ADR-0034's census (2026-07-12, master `a6c5a9e`) found `bin/` speaking three grammars at
once: three subsystem nouns (`board`, `classify`, `gate`), one verb-first orphan
(`add-backlog`), five prefixed siblings (`session-*`), and two module CLIs. Six subsystems
that already have engines (`spec`, `goal`, `stats`, `mega`, `queue`, plus the new `learn`)
have no bin entry at all. The Learn leg's reader/closer (`weekend-batch.sh`) lives in
`lib/queue/`, an Execute-leg directory, and the dotfiles `weekend-debt-paydown` skill
reaches it via a deep `lib/queue/...` path -- itself a SPEC-184 violation. The stats skill
sits at `lib/stats/skill/SKILL.md`, where `install.sh`'s `skills/*/SKILL.md` glob never
finds it: a phantom surface that ships but never installs.

## Solution

Execute ADR-0034 decisions 1, 7, and 8 in one wave (this spec builds nothing new; it
regroups what exists -- the ADR text wins over any conflicting phrasing here):

1. **`lib/learn/` + `bin/learn` (decision 1).** `git mv lib/queue/weekend-batch.sh
   lib/learn/` (history preserved); `lib/learn/learn.sh` dispatches
   `debt <list|collect|mark-paid>` to it verbatim. `propose`/`drain` are reserved verbs
   that REFUSE with "ships in SPEC-195/196" (exit 1), never a silent no-op.
2. **One grammar for bin/ (decision 7).** The five `bin/session-*` entries collapse into
   `bin/session <verb>` (lib/session/session.sh gains `report`/`semantic` forwarding
   beside the existing `observe`/`recall`/`intel`; deep lib paths unchanged).
   `bin/add-backlog` retires; the verb folds as `board promote` (board.sh forwards to
   `lib/board/bin/add-backlog` verbatim). NO alias survives. Missing subsystem entries
   are created: `bin/spec`, `bin/goal`, `bin/stats`, `bin/mega`, `bin/queue` (thin
   forwarders, SPEC-184 shape; `bin/stats` forwards through `uv run --project`).
   Module CLIs keep module names: `prose-rag`, `worktree-provision` untouched.
3. **Stats skill relocates (decision 8).** `lib/stats/skill/SKILL.md` ->
   `skills/stats/SKILL.md`, where the install glob picks it up on both install paths.
4. **Every call-site repoints, three repos.** dwarves-kit (tests, install.sh CLI-shim
   list, docs, the session-intel-weekly launcher, stats operator-guidance strings);
   dotfiles (weekend-debt-paydown, learning-router, cc-observe skills -- companion PR);
   ops-toolkit (verify-only: `_meta/board`/`board-all` already point at `bin/board`;
   the vps-mon session-intel-bridge calls `~/.local/bin/session-report`, repointed in
   its own repo follow-up if a real hit -- see Verification (e)).

## Scope

**In:** the weekend-batch move; the full bin/ regroup (collapse, fold, complete); the
skills relocation; call-site repoints (three repos checked); install.sh shim wiring in
the same commit as the renames; docs/consumer-contract.md update.
**Out:** `propose`/`drain` implementations (SPEC-195/196); any tool behavior change;
module renames; the scheduler (SG-10); `bin/config` (SG-08).
**Not:** folding harvest/backlog-stage hooks into lib/learn (capture-side, ADR-0034
decision 1); a `kit` uber-dispatcher (rejected, kit-modularity SG-03); "improving" any
tool while moving it.

## Quality bar

A regroup, not a rewrite: every tool's behavior, flags, and outputs are byte-level
unchanged; only paths and entry grammar move. The one deliberate exception class:
user-facing guidance strings that NAME a retired surface (`add-backlog` usage hints, the
staging-buffer header, stats `--help` epilogs) are repointed to the live grammar, because
leaving them directs an operator at a dead command (recorded in the impl-notes).

## Acceptance criteria

| # | Criterion |
|---|---|
| AC1 | `bin/learn debt list|collect|mark-paid` green on the SPEC-126 fixture suite (tests/test-weekend-batch.sh through the new path) |
| AC2 | each `bin/session <verb>` green on its tool's existing smoke test |
| AC3 | `bin/board promote` green on the add-backlog fixture (empty-repo smoke + install-clis test) |
| AC4 | BEFORE/AFTER bin/ census table matches the ADR-0034 target list exactly (12 entries: 10 subsystem + 2 module; `config` lands SG-08) |
| AC5 | three-repo grep-audit: ZERO stale references to the retired surfaces (`lib/queue/weekend-batch.sh`, top-level `bin/session-*`, standalone `add-backlog` invocations) on live surfaces |
| AC6 | NCs: every retired path exits non-zero / is provably absent when invoked, captured |
| AC7 | stats skill installs: `skills/stats/SKILL.md` exists and the install glob picks it up |
| AC8 | full suite green in dwarves-kit; dotfiles repo checks green |

## Verification

```bash
bash tests/test-weekend-batch.sh          # AC1 (WB= lib/learn path)
bash lib/session/observe/tests/smoke.sh   # AC2 (observe + semantic)
bash lib/session/intel/tests/smoke.sh     # AC2 (intel)
bash lib/session/recall/tests/run-tests.sh 2>/dev/null || bash lib/session/recall/tests/*.sh  # AC2 (recall)
bash lib/session/observe/tests/test-vps-report.sh  # AC2 (report)
bash tests/test-install-clis.sh           # AC3 + shim wiring
ls -1 bin/                                # AC4 census
bash tests/test-hooks.sh && bash tests/test-meta.sh  # AC8
# AC5/AC6: see docs/verification/loop-04-surface-consol.md (grep-audit + NC table)
```

## After state

`ls bin/` reads as one kit: `board classify gate goal learn mega queue session spec
stats` + `prose-rag worktree-provision`. The Learn leg has its decision-1 home with
`debt` live and `propose`/`drain` reserved-refusing for SPEC-195/196. The stats skill
installs on both paths. No consumer anywhere references a retired surface.

## Decision Log

- Guidance-string repoints (see Quality bar) are the recorded deviation from strict
  byte-level-unchanged; everything else moves verbatim.
- `lib/stats/tests/*`'s `../cc-backlog/bin/add-backlog` cross-check references the
  long-retired ops-toolkit sibling and self-SKIPs; repointing it at the kit's own
  engine would change which env vars the check needs (CC_BACKLOG_* vs BACKLOG_STAGE_*)
  -- a behavior change, out of scope. Left as a dormant skip.
