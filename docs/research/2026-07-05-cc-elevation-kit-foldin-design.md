---
title: "cc-elevation fold-in: shape framework + naming convention + kit structure for moving cc-* tools into dwarves-kit"
date: 2026-07-05
purpose: >
  Design for folding the ~14 cc-* / cc-elevation-adjacent tools into dwarves-kit
  properly, rather than as a flat dump. Grounds the "harness-kit consolidation"
  direction flagged in runner-fastpath NOTES.md (2026-07-05, "apply the same
  engine->kit / data->ops-toolkit split to the rest of cc-elevation") with an
  actual inventory + a shape framework, ahead of drafting a follow-up mega-goal.
  Design only; no code moves yet.
source_repos: [ops-toolkit, dwarves-kit]
refresh_cadence: none
next_review: null
status: active
---

# cc-elevation fold-in: three-shape framework

## Problem

runner-fastpath (this session, same day) moved `board`, the queue launcher, and
`ledger-observatory` into dwarves-kit under one principle: generic harness ENGINE
lives in the kit, personal DATA stays in ops-toolkit as config the kit reads at
runtime. Han asked whether the same treatment should apply to the rest of
cc-elevation , the ~14 `cc-*` tools that currently live in ops-toolkit `tools/`
and are deployed via a separate snapshot mechanism (see below). This doc answers
"what does properly folded in actually look like", grounded in what already
exists, before any mega-goal gets drafted.

## What already exists (do not rebuild)

- **The current deploy mechanism**: cc-* tools are NOT invoked from ops-toolkit
  source at runtime. `tools/redeploy.sh` snapshots `ops-toolkit/tools/cc-*` via
  `git archive origin/main` into `~/.local/share/cc-elevation/tools/`, branch-
  independent, then symlinks into `~/.local/bin` and wires hooks in
  `~/.claude/settings.json`. This snapshot-deploy step is itself a fold-in
  mechanism, worth reusing or deliberately replacing, not reinventing blind.
- **The operator guide**: `research/2026-06-15-cc-elevation-suite.md` , hooks
  table, enable/disable env knobs, the deploy model. Read before designing
  further; it is the current-state reference this doc builds on.
- **What "already in the kit" actually looks like** (the reference examples
  runner-fastpath's NOTES cited as precedent, verified this session): none of
  them are standalone CLIs.
  - `gate-ledger` = `dwarves-kit/lib/gate-ledger.sh`, invoked as a CALL-BY-PATH
    sibling subprocess (`bash "$DIR/gate-ledger.sh" ...`, `$DIR` resolved from
    the caller's own `BASH_SOURCE`) by other kit lib scripts , e.g.
    `lib/orchestrate.sh:522`, `lib/mega-merge.sh:50,74`,
    `lib/lane-classify.sh:48`. NOT sourced-into-caller (corrected 2026-07-05
    after a deploy-mechanism check; `lib/*.sh` files are call-by-path HELPERS,
    a distinct role from `hooks/*.sh`, the actual settings.json entry points ,
    see the framework correction below).
  - `advisor`, `meta-agent` = `dwarves-kit/agents/{advisor,meta-agent}.md`,
    subagent DEFINITIONS dispatched via `Agent`/`/kit:review-team` etc.
  - `review-findings-memory` has no runtime artifact yet at all , spec only
    (`docs/specs/SPEC-144-review-findings-memory.md`, unmerged branch).
  - This matters: the standalone-CLI-plus-hook shape every cc-* tool uses today
    is a DIFFERENT shape from anything already living in the kit. Assuming they
    all become `tools/<name>/` CLIs (the board/ledger-observatory precedent)
    would be copying the wrong reference.

## Inventory (this session's fork research, 2026-07-05)

| Tool | Location | Lang | Size | Purpose | Shape | Tests |
|---|---|---|---|---|---|---|
| cc-backlog | tools/cc-backlog | bash | 1 file / 77 LOC | SessionEnd hook, stage backlog candidates | flat script | 1 |
| cc-citation-guard | tools/cc-citation-guard | bash | 1 / 69 | Stop hook, verify file:line citations | flat script | 0 |
| cc-context-hooks | tools/cc-context-hooks | bash | 1 / 52 | UserPromptSubmit, temporal + JIT skill hints | flat script | 0 |
| cc-harvest | tools/cc-harvest | bash | 3 / 313 | PreCompact/SessionEnd ledger harvest | multi-file | 2 |
| cc-intel | tools/cc-intel | bash | 1 / 110 | weekly digest (launchd) | flat + deploy/ | 0 |
| cc-money-gate | tools/cc-money-gate | bash | 1 / 45 | PreToolUse money-file gate | flat script | 0 |
| cc-observe | tools/cc-observe | bash | 2 / 325 | usage/latency from transcripts (3 bins: cc-observe, cc-semantic, cc-vps-report) | multi-bin | 1 |
| cc-plugin-check | tools/cc-plugin-check | bash | 1 / 268 | plugin freshness check | flat script | 0 |
| cc-recall | tools/cc-recall | python | 2 / 284 | turn-grouped transcript recall | small pkg | 1 |
| cc-self-improve | tools/cc-self-improve | bash | 22 / 1326 | Hermes skill self-improvement loop | full sub-project | 11 |
| cc-workflows | tools/cc-workflows | bash | 1 / 10 | pointer to saved Workflow scripts | near-empty | 0 |
| cc-worktree-provision | tools/cc-worktree-provision | bash | 1 / 98 | manual worktree env symlink | flat script | 0 |
| verify-claim | tools/verify-claim | bash | 1 / 48 | adversarial skeptic-panel CLI | flat script | 0 |
| meta-agent (CLI) | tools/meta-agent | bash | 1 / 66 | draft a subagent spec via `claude -p --draft` | flat script | 0 |

Two findings not in the original NOTES.md triage:

1. **A live duplicate.** `tools/meta-agent` (the CLI above) and dwarves-kit's
   `kit:meta-agent` agent do the literal same job , draft a subagent/sub-goal
   spec from a description , via two different mechanisms. No design needed
   here: retire the ops-toolkit CLI, point to the kit agent.
2. **A real overlap, not just adjacency.** `cc-observe` and `cc-recall` both
   parse Claude Code transcripts (usage/latency vs. turn-grouped recall). This
   is the one place a merge is earned , NOT a case for forcing an artificial
   "object group" elsewhere.

## The three-shape framework (corrected 2026-07-05 post-resolution)

Matches what is ALREADY proven, in the kit and in this session, rather than
inventing a fourth shape. **Correction from the first draft**: "hook-lib" was
one name for two distinct kit directories. `dwarves-kit/install.sh:167-321`
merges the kit's OWN `settings.json` hook entries into a consumer's
`~/.claude/settings.json` at the fixed path `~/.claude/dwarves-kit/hooks/<x>.sh`
, so `hooks/` is the real event-entry-point directory a settings.json hook
fires. `lib/*.sh` files (like `gate-ledger.sh`) are call-by-path HELPERS a hook
or another lib script invokes, never a hook target themselves. The shape
table below splits these two roles instead of conflating them:

| Shape | Fits when | Precedent |
|---|---|---|
| **`hooks/<name>.sh`** (settings.json entry point) | Directly fired by a Claude Code hook event | none yet in the kit , cc-backlog etc. would be the FIRST |
| **`lib/<name>.sh`** (call-by-path helper) | Shared logic a hook or another lib script invokes, no event binding itself | `lib/gate-ledger.sh` |
| **Subagent `.md`** (dispatched, not executed) | The job's core work IS an LLM reasoning/judgment task | `agents/advisor.md`, `agents/meta-agent.md` |
| **Standalone `tools/<name>/` CLI** (own tests/docs/state) | Human- or cron-invoked, generic, substantial enough to need its own proof-of-done | `tools/board/`, `tools/ledger-observatory/` (this session) |

Ponytail check: grouping for its own sake is an anti-pattern. The hook-event
cluster below has no shared data model across different hook events (SessionEnd
vs Stop vs UserPromptSubmit vs PreCompact); forcing them into one umbrella
"hooks" object would relabel complexity, not reduce it , each stays its own
`hooks/<name>.sh` file. Only `cc-observe` + `cc-recall` have an earned partial
merge (a shared transcript-parsing helper, resolved below , NOT one CLI).

## Per-tool disposition (RESOLVED 2026-07-05)

| Tool | Shape | Rationale |
|---|---|---|
| cc-backlog | `dwarves-kit/hooks/` | deterministic SessionEnd staging; FIRST tool to land in `hooks/` (no precedent yet) |
| cc-citation-guard | `dwarves-kit/hooks/` | deterministic Stop-hook verify |
| cc-context-hooks | `dwarves-kit/hooks/` | deterministic UserPromptSubmit hints |
| cc-harvest | `dwarves-kit/hooks/` (multi-file OK) | deterministic PreCompact/SessionEnd harvest, already 3 files |
| cc-observe | `tools/` CLI, unchanged surface | keeps its 3 bins (cc-observe/cc-semantic/cc-vps-report); aggregate stats, table output |
| cc-recall | `tools/` CLI, unchanged surface | point-lookup search over transcripts; stays SEPARATE from cc-observe (different mental model: "stats" vs. "find this one thing") |
| cc-observe + cc-recall shared logic | extract ONE shared transcript-parsing lib both call | the only real duplication is the JSONL turn-parsing routine, not the capability; resolved as (b) from the original open question, not a CLI merge |
| cc-self-improve | own `tools/` subtree, moved wholesale | confirmed clean (22 files, 11 tests); ONE hardcoded fallback (`lib/surface.sh:9`, `CC_SI_MEMORY_LEDGER` default), same trivial env-default fix as ledger-observatory's adapters |
| cc-plugin-check | `tools/` CLI | cron/ad-hoc invoked, generic, no LLM judgment |
| cc-intel | `tools/` CLI (keeps its own launchd deploy/) | cron-invoked digest, generic |
| verify-claim | **new kit subagent** (not a retirement) | confirmed NO existing kit agent does this job (checked 5 verify-shaped agents by grep + hand-read: all re-execute/critique a specific code/spec/task/doc artifact, none run an N-model majority-vote panel over an arbitrary free-text claim); porting means REDESIGNING the current N-parallel-`claude -p`-subprocess script as an agent that itself fans out N parallel skeptic dispatches , a real implementation decision, not a file move |
| `tools/meta-agent` (CLI) | **retire** | duplicate of `kit:meta-agent`, zero design needed |
| cc-workflows | drop | 10 LOC, not worth a home |
| cc-worktree-provision | defer | already flagged kit-shaped but off the runner critical path |
| review-findings-memory | defer | not built yet, spec-only; shape decision waits for implementation |
| cc-money-gate | stays ops-toolkit | tenant/personal-path bound (unchanged from original NOTES triage) |

## Open questions , RESOLVED (2026-07-05, two parallel forks)

1. **cc-observe + cc-recall merge , RESOLVED: (b), not (a).** Extract the
   shared transcript/turn-parsing routine into one lib both CLIs call; keep
   two separate CLIs. Both already have their own JSONL-parsing routine over
   the same schema (`cc-observe`'s single-pass scan vs. `cc-recall`'s
   `load()`/`_role()`/`_ts()`), but the USE differs entirely: aggregate
   quantitative reporting (tables: usage/latency/cost/archetypes/error rates)
   vs. point-lookup search ("find me this one past thing", explicitly scoped
   in cc-recall's own docstring as distinct from both `prose-rag` and, now,
   `cc-observe`). Forcing one binary would conflate two different mental
   models a user types against.
2. **verify-claim vs. existing kit reviewer agents , RESOLVED: no duplicate.**
   Confirmed via source read (not just descriptions) against 5 candidate kit
   agents + `recheck-verifier`/`advisor` by hand: every kit verify-shaped agent
   re-executes or critiques a SPECIFIC code/spec/task/doc artifact against a
   recorded command or diff. verify-claim takes an ARBITRARY free-text claim
   through N independent haiku skeptics (default-refute-if-uncertain,
   majority vote). Different object, different mechanism. Becomes a new kit
   subagent, but porting requires redesigning the fan-out (see disposition
   table) , flag this as real implementation work in the eventual mega, not a
   trivial file move.
3. **Deploy mechanism , RESOLVED: `redeploy.sh`'s snapshot dance becomes
   unnecessary for anything that lands in the kit as a hook.** `gate-ledger.sh`
   is called by path (`bash "$DIR/gate-ledger.sh" ...`), not sourced; more
   importantly `dwarves-kit/install.sh:167-321` already merges the kit's OWN
   `settings.json` hook entries into a consumer's `~/.claude/settings.json` at
   the FIXED path `~/.claude/dwarves-kit/hooks/<name>.sh` (comment at
   `install.sh:167-168` states this directly). Once cc-backlog/cc-citation-guard/
   cc-context-hooks/cc-harvest move into `dwarves-kit/hooks/`, re-running the
   kit's own `install.sh` wires the hook automatically , ops-toolkit's
   git-archive-snapshot-symlink dance is not needed for these four. (It may
   still matter for whatever STAYS a standalone ops-toolkit CLI, e.g.
   cc-money-gate , unaffected by this correction.)
4. **cc-self-improve's Hermes coupling , RESOLVED: clean, trivial fix.** Full
   grep sweep of `lib/`, `config/`, `hooks/`, `bin/` found exactly one
   hardcoded personal default: `lib/surface.sh:9`
   (`CC_SI_MEMORY_LEDGER` falls back to
   `$HOME/workspace/<owner>/ops-toolkit/_meta/learned-ledger.md`), already
   env-overridable, just needs the default flipped to empty/opt-in (identical
   fix shape to SG-05K's ledger-observatory adapter-default work). No hardcoded
   Hermes hostname/URL found anywhere despite the tool's name , the mechanism
   is generic `claude -p` calls. The personal deploy runbook
   (`deploy/macos/cc-curator-runbook.md`) stays ops-toolkit-side per
   deploy-follows-source, not a code blocker.
5. **Sequencing vs. runner-fastpath , STILL HOLDS.** runner-fastpath is
   mid-flight (paused, not converged) as of this design pass; this stays a
   separate mega, drafted only once runner-fastpath's 13 sub-goals ship.

## Kit structure + naming convention (2026-07-05, Han-directed)

Han's point: `cc-` = "claude code". The kit is meant to be agent-agnostic (it
installs into any consumer's `~/.claude` via `install.sh`; per the omp-adoption
note, other agents read the same tree). So `cc-` is the wrong prefix for
anything that lands in the kit, and the fold-in is the moment to fix naming +
grouping, not after. Two decisions:

### Decision 1 , naming: name by FUNCTION, never by host-agent

The kit already does this implicitly , `ship-gate`, `safety-gate`,
`lane-classify`, `gate-ledger`, `advisor`, `meta-agent` carry zero agent
prefix. The rule, made explicit:

1. **Drop `cc-` on any artifact that moves into the kit.** Never encode the host
   agent (`cc`, `claude`, `opencode`, `pi`) in a kit artifact name.
2. **Name by function** (verb or function-noun): `citation-guard`,
   `plugin-check`, `worktree-provision`, `backlog-stage`.
3. **When the artifact's OBJECT is the agent session/transcript, use the neutral
   `session-` noun** , agent-agnostic (a pi/opencode/CC run is still a
   "session"), and it disambiguates (`observe` alone is meaningless; the kit's
   bare-verb `explain.sh`/`pitch.sh` are self-evident, `observe`/`recall` are
   not). So `cc-observe -> session-observe`, `cc-recall -> session-recall`,
   `cc-intel -> session-intel`, the shared parser -> `lib/session/`.
4. **Scope of the rule = the KIT ONLY.** Tools that legitimately STAY in
   ops-toolkit as personal Claude-Code config (`cc-money-gate`) may keep `cc-`;
   there it correctly means "my claude-code money-file guard", not a kit
   artifact. Do not rename ops-toolkit-resident cc- tools for consistency's
   sake , the prefix is accurate there.

### Decision 2 , structure: type-first (loader-mandated), subsystem-second (only where free)

The kit's top level is organized by artifact TYPE (`lib/ hooks/ agents/
commands/ skills/ tools/ rules/`). This is NOT a stylistic choice , Claude
Code's loader REQUIRES it: `agents/*.md`, `commands/*.md` (namespaced `kit:`),
`skills/*/SKILL.md` are discovered by fixed convention, and each `hooks/` entry
is wired into `settings.json` by explicit path. You cannot move those under a
`board/` or `session/` subsystem dir , the loader would stop finding them.

So subsystem grouping is possible ONLY in the two dirs the loader does not
depth-constrain:

- **`lib/`** , call-by-path (`bash "$DIR/x.sh"`, `$DIR` from `BASH_SOURCE`)
  resolves at any depth. This is SG-09's exact target and the one real regroup.
- **`tools/`** , already one-subtree-per-tool; cc-* CLIs each get their own
  `tools/<function-name>/`. No further grouping needed.

**`hooks/`, `agents/`, `commands/` stay FLAT.** They are addressed by explicit
path or namespace, function-naming is already the organizer, and subdividing
them would add config churn (rewire every `settings.json`/`hooks.json` path, risk
the agent/command loader's non-recursive scan) for zero navigation win. Ponytail:
do not subdivide 22 hooks that are each already individually addressed by config.

Net: the ONLY structural change the fold-in introduces is the `lib/` subsystem
regroup , which SG-09 already owns. Everything else slots into existing
type-dirs by its new function name.

### The `lib/` subsystem map (= SG-09 spec, now shared with the fold-in)

```
lib/
  board/       board.sh board-mirror.sh board-writeback.sh parse-board.sh backlog.sh
  queue/       orchestrate.sh queue.sh weekend-batch.sh
  gate/        gate-ledger.sh proof-gate.sh proof-ledger.sh proof-table-gen.{py,sh}
               dispatch-gate.sh quiz-gate.sh coverage-delta.sh verif-counts.sh mutation-smoke.sh
  classify/    lane-classify.sh role-classify.sh significance-classify.sh
               task-type-classify.sh route-suggest.sh
  spec/        spec-index.sh spec-next.sh
  goal/        goal-drafts.sh goal-registry.sh mega-merge.sh stack-merge.sh handoff/ handoff-gen
  telemetry/   lane-telemetry.sh kit-log-dir.sh
  session/     parse-transcript.sh          <- NEW: the earned cc-observe+cc-recall shared parser
  (root)       adopt.sh explain.sh pitch.sh precedent.sh   <- orphans, no cluster, stay flat
```

Regroup , resolution strategy (CORRECTED 2026-07-05 after advisor P5 caught a
false-green in the naive "one shim at the old flat root" plan): the kit's lib
scripts resolve their SIBLINGS from their OWN `BASH_SOURCE` dir, not a fixed
lib-root , e.g. `orchestrate.sh` does `ORCH_DIR=$(dirname ${BASH_SOURCE})` then
`bash "$ORCH_DIR/gate-ledger.sh"`, and `mega-merge.sh` does
`source "$MM_DIR/kit-log-dir.sh"` with a FATAL `exit 1` on miss. So once a
CALLER moves into a subsystem dir, its `$DIR` becomes that subsystem dir, and
`$DIR/<callee>.sh` looks for the callee AS A SIBLING in the new dir , a shim at
the OLD flat root is never consulted. A naive "one symlink per file at
`lib/<old-name>.sh`" therefore breaks the busiest engines (`orchestrate.sh`,
`mega-merge.sh`, `lane-classify.sh`, `proof-gate.sh` all self-resolve
cross-subsystem siblings), AND the obvious NC (`rm lib/gate-ledger.sh` root
shim) does NOT falsify it (moved callers never look there). Two valid fixes, SG-01's
spec PICKS one (this makes SG-01 `Design: bearing`, not obvious):
(a) introduce a shared lib-root resolver every cross-subsystem call routes through
(one small edit per caller; robust; drops the "zero call-site edits" promise), OR
(b) place a shim INSIDE every subsystem dir that hosts a caller, one per
(caller-subsystem, callee) pair (`lib/queue/gate-ledger.sh -> ../gate/gate-ledger.sh`
etc.; keeps zero call-site edits; more symlinks). Either way the GATE is the full
kit suite green AND an NC that MOVES a caller+callee into different subsystems and
confirms the cross-subsystem call still resolves (specifically exercise
`orchestrate.sh` + `mega-merge.sh`), not a root-shim removal. Orphans
(`adopt/explain/pitch/precedent`) have no cluster , forcing a `misc/` would be
grouping for its own sake, they stay at `lib/` root.

### cc-* fold-in landing names (applies Decisions 1+2 to the disposition table)

| Was (ops-toolkit) | Becomes (kit) | Type-dir |
|---|---|---|
| cc-backlog | `hooks/backlog-stage.sh` | hooks/ (flat) |
| cc-citation-guard | `hooks/citation-guard.sh` | hooks/ (flat) |
| cc-context-hooks | `hooks/context-hints.sh` (UserPromptSubmit; coexists with the kit's SessionStart `context-readiness.sh`, different event, verified) | hooks/ (flat) |
| cc-harvest | `hooks/harvest.sh` (+ its helpers) | hooks/ (flat) |
| cc-observe | `tools/session-observe/` (keeps its 3 bins) | tools/ |
| cc-recall | `tools/session-recall/` | tools/ |
| (shared parser) | `lib/session/parse-transcript.sh` | lib/session/ |
| cc-intel | `tools/session-intel/` (keeps its launchd deploy/) | tools/ |
| cc-plugin-check | `tools/plugin-check/` | tools/ |
| cc-self-improve | `tools/skill-curator/` (function = curates/improves skills, not sessions; rename off `self-improve` which reads as recursive-on-itself) | tools/ |
| cc-worktree-provision | `lib/goal/worktree-provision.sh` OR `tools/worktree-provision/` (defer; off critical path) | lib/goal or tools/ |
| verify-claim | `agents/claim-verifier.md` (NEW subagent; fan-out redesign, not a file move) | agents/ (flat) |
| meta-agent (CLI) | retire (dup of `kit:meta-agent`) | , |
| cc-workflows | drop (10 LOC) | , |
| cc-money-gate | stays ops-toolkit, keeps `cc-` | (not kit) |

### Consequence for SG-09

SG-09 (runner-fastpath's last open sub-goal) and this fold-in both rewrite
`lib/`. Doing SG-09 now under a bare "regroup 32 files" spec, then the fold-in
re-touching `lib/` to add `lib/session/`, is two passes over the same tree.
Cleaner: **rehome SG-09 into the cc-elevation mega as its sub-goal 0** , the
taxonomy above is decided ONCE, SG-09 lands the existing-file regroup + shims,
then the cc-* hooks/tools/agent land into the same taxonomy. runner-fastpath
then closes at 12/13 with 09 explicitly rehomed (not dropped). Alternative: keep
SG-09 in runner-fastpath, but pin it to THIS map so the fold-in inherits it. The
first is less churn; flagging both for Han.

## Not decided here

Sub-goal boundaries / wave split of the mega (the fold-in is ~14 tools + the
lib/ regroup, roughly runner-fastpath-sized; likely waves = SG-09 lib/ regroup
FIRST, then hooks-landing / tools-landing CLIs / the skill-curator move / the
claim-verifier agent-redesign as parallel-ish waves the way runner-fastpath
split board/runner/observatory). The cc-observe+cc-recall shared-parser's exact
interface (what `lib/session/parse-transcript.sh` returns to each caller) is a
real design task for the builder. Whether `cc-worktree-provision` lands as a
`lib/goal/` helper or its own `tools/` CLI. Whether SG-09 rehomes or stays
pinned. All resolved when the mega gets drafted , which is now UNBLOCKED
(runner-fastpath shipped 12/13; only the rehomed/pinned SG-09 straddles).
