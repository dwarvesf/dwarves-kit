---
title: "dwarves-kit: composable, shell-wired modules , the MIDDLE level (a-la-carte install/wire, NOT a monolithic product)"
date: 2026-07-05
purpose: >
  Design for how dwarves-kit graduates from a scattered pile of SDD scripts to a
  COMPOSABLE toolkit , explicitly the MIDDLE level between (0) today's scatter and
  (2) a monolithic "product" with one uber-binary + one central config that ships
  everything. Han's correction (2026-07-05): full consolidation makes the kit FEEL
  abnormally big; a consumer should install + wire only the pieces they want, via
  shell, a-la-carte. Captures four coupled decisions from the cc-elevation fold-in
  follow-ups, RE-FRAMED to the middle level: per-module installable commands (not an
  uber-facade), install/wire-time enablement (not a central runtime feature-registry),
  config-awareness for the already-parked team-mode, and a philosophy/README/onboarding
  refresh. Sequenced AFTER kit-foldin (whose lib/ subsystem regroup is the structural
  precondition). Design only; no code. Drafted ahead of a follow-up mega.
source_repos: [dwarves-kit, ops-toolkit]
refresh_cadence: none
next_review: null
status: active
---

# dwarves-kit: composable, shell-wired modules (the middle level)

## Problem

kit-foldin (the cc-elevation fold-in) absorbs the last generic harness tools into
dwarves-kit and regroups `lib/` into subsystems. Once it lands, the kit is coherent
enough to ask: how should a consumer ADOPT it? Han raised four follow-ups , command
surface, feature enablement, team-awareness, docs , and rejected the obvious answer.

**The rejected framing (2026-07-05): "kit as a product."** Consolidating everything
behind ONE `kit` uber-binary + ONE central config that ships the whole suite makes the
kit FEEL abnormally big , a consumer perceives a heavy appliance they must adopt whole,
which is the opposite of the "shallow and wide" + "minimum-infra-first" theses the kit
is built on. Han's word: keep the pieces **install-and-wired by shell, a-la-carte**;
don't merge them into one large thing.

**The target: the MIDDLE level.** Three levels exist:

| Level | Shape | Verdict |
|---|---|---|
| 0 , today | scattered `lib/*.sh` invoked by path; no coherence, hard to discover | too raw |
| 1 , **MIDDLE (this note)** | each capability is an independently installable + wireable shell module; light conventions make them discoverable + consistent; you compose only what you need | **the target** |
| 2 , "product" | one `kit` uber-binary + one central runtime feature-registry + install-everything onboarding | too heavy , feels big, forces whole-suite adoption |

The kit is a **toolbox you pick from**, not an **appliance you switch on**. Every
decision below is re-framed to Level 1. Downstream of kit-foldin: the module boundaries
ARE the `lib/` subsystem dirs (SG-01), and enablement covers the final tool set.

## Grounding: what the kit is today (measured 2026-07-05)

- **Language: bash-first, by design.** 68 shell files (34 `lib/`, 17 `hooks/`, plus
  the subsystem scripts) + 3 Python (`proof-table-gen.py`, ledger-observatory) +
  markdown prompts (24 `agents/`, 30 `commands/`). Bash-over-binaries is a stated
  thesis (the parked "in-kit DAG executor" note cites PHILOSOPHY "shallow and wide"
  + the bash thesis as the reason NOT to build a runtime). Python is the deliberate
  exception where the ecosystem earns it (DuckDB, embeddings).
- **Command surface: scattered.** Most `lib/` scripts are invoked by path
  (`bash lib/gate-ledger.sh ...`). Two subsystems already have a real sub-command
  shape , `board <render|next|queue|mirror|writeback>` and `orchestrate queue` ,
  proving the pattern works.
- **Config: none central.** The de-facto config is ~20 scattered `${ENV_VAR:-default}`
  reads (`DWARVES_KIT_LOG_DIR`, `HERMES_BIN`, `WAVE_CAP`, `OPT_REGISTRY`, ...) plus
  exactly two opt-in gates: `boards.txt bridge=on` (per-repo Hermes mirror) and
  `heartbeat.every`. There is NO "which features are enabled" surface.
- **Hooks: all-or-nothing.** 17 hooks; `install.sh` wires them all into a consumer's
  settings.json at install; there is no per-hook disable.

## Decision A , per-subsystem standalone commands (NOT a `kit` uber-facade)

Han's "gom lại thành scope cụ thể, cân nhắc sub-command" , scoped, but at the MIDDLE
level. NOT a language rewrite (bash-first stays), and NOT one `kit` uber-binary that
owns everything (that is the Level-2 monolith Han rejected , it makes the pieces feel
inseparable). The middle-level answer: **each subsystem is its own standalone,
independently installable command with its own sub-verbs** , exactly the shape
`board` and `orchestrate` ALREADY have:

```
board    <render|next|queue|mirror|writeback>   # already standalone (lib/board/)
orchestrate <queue|status>                       # already standalone (lib/queue/)
gate     <record|plan|proof|...>                 # lib/gate/*  , its own entry
classify <lane|role|task-type|significance>      # lib/classify/*
spec     <index|next>                            # lib/spec/*
goal     <draft|registry|merge>                  # lib/goal/*
session  <observe|recall|intel>                  # tools/session-* (kit-foldin)
```

- **Shape:** each SG-01 subsystem dir ships a thin `<subsystem>` entry (`board`-style:
  `<subsystem> <verb> "$@"` -> `lib/<subsystem>/<verb>.sh`). You install ONLY the
  subsystems you use , `session` without `bridge`, `gate` without `board`, whatever.
  The subsystem dirs from SG-01 are the module boundaries; the entry is ~15 lines each.
- **The optional `kit` dispatcher is DISCOVERY SUGAR, not the surface.** At most a
  ~20-line `kit` that (a) `kit list` shows installed modules, (b) `kit <sub> <verb>`
  FORWARDS to the standalone `<sub>` if present. It NEVER becomes a required front door
  and NEVER makes the modules inseparable , delete it and every module still works
  standalone. Skip it entirely if it does not earn its keep; the standalone commands
  are the real surface.
- **Back-compat:** every existing `bash lib/<x>.sh` call-site keeps working (the entries
  are additive; the SG-01 resolver keeps direct paths alive). Standalone entries are the
  HUMAN surface; internal call-by-path stays.
- **Slash commands unaffected:** `/kit:*` (the 30 `commands/`) are a separate Claude Code
  surface, stay as-is. The standalone `<subsystem>` commands are the SHELL surface (cron,
  CI, a human in a terminal).
- **Ponytail:** only subsystems with 2+ verbs earn a grouped entry; single-purpose orphans
  (`adopt`, `explain`, `pitch`) stay bare standalone scripts. Grouping for its own sake ,
  and a top uber-binary that swallows them , are both the anti-pattern here.

## Decision B , enablement by INSTALL/WIRE (shell, a-la-carte), a light manifest to record it

Han's "check config để xem chức năng nào enable, chia essential vs optional" , YES to a
config that says what's on and tiers essential vs optional, but the ENABLEMENT MECHANISM
is shell install/wire per-module, NOT a monolithic runtime registry every module consults
(that is the Level-2 "big product" feel Han rejected).

- **Mechanism (middle level):** a consumer WIRES the modules they want via shell , the
  core install always wires the spine; each optional module has its own opt-in wire step
  (`install.sh --with board,stats` or a per-module `board/install`). A **light
  `kit.toml [modules]` manifest** RECORDS what is enabled + its tier , for discovery
  (`kit list` / `install.sh --status`) and so re-running install re-wires the same set.
  The manifest is a record that DRIVES shell wiring; it is NOT a runtime feature-registry
  that every hook reads on every event. This generalizes the existing per-feature opt-in
  gates (`bridge=on`, `heartbeat.every`) , which are already the a-la-carte pattern , not
  a new central idea layered on top.
- **Essential (always wired, the SDD spine):** `spec`, `execute`, `review`, `ship`;
  `gate-ledger` + the `ship-gate` hook; `lane-classify` + `proof-gate`; the core task/
  integration/acceptance verifiers. The kit is pointless without these; they are not
  optional and not in the manifest's toggle set.
- **Optional (opt-in wire step each):** `board`, `queue`/`orchestrate`,
  `ledger-observatory`, the Hermes `bridge` (mirror/writeback , the reference a-la-carte
  module: valuable, off by default, one opt-in, the `bridge=on` pattern this generalizes),
  `quiz-gate`, `weekend-batch`, `advisor` over-suggest, the `session-*` tools, `team-mode`,
  and the cosmetic hooks (`slop-cleaner`, `statusline`, `notification`, `auto-format`,
  `codebase-index`). A consumer who wants just SDD installs the spine and NOTHING else
  gets wired; a power user opts into the cockpit + stats + bridge. (prose-rag is NOT
  here , it stays a personal ops-toolkit tool; see kit-foldin NOTES.)
- **The hook problem (why install-time, not runtime):** hooks are all-wired today. Middle-
  level fix: `install.sh` wires ONLY the hooks whose module the consumer opted into , an
  un-installed module's hook is never written into `settings.json`, so there is nothing to
  gate at runtime. (A `feature_enabled <name> || exit 0` first-line guard is the FALLBACK
  only for a hook too entangled to conditionally wire , prefer not wiring it at all. This
  keeps a consumer's `settings.json` showing only what they actually run, reinforcing the
  "small, not a big appliance" feel.)
- **Tiering vocabulary:** essential / optional is the floor. A third tier ,
  "recommended-on" optionals (board, stats) vs "off-by-default" optionals
  (bridge, team-mode) , is worth it ONLY if the install UX (Decision D) uses it;
  otherwise two tiers suffice. Decide at build time, don't pre-bake.

## Decision C , team-mode: config-aware, still PARKED

Team collaboration is NOT unplanned , it was fully audited and designed 2026-07-04 as
**"attestation, not sync"** (kit `_meta/BACKLOG.md` L185; full design ops-toolkit
`research/2026-07-04-pxpipe-plannotator-improve-absorption.md` §5). The three walls
and the designed seams:

| Wall (solo assumption) | Team seam (designed, not built) |
|---|---|
| gate-ledger is machine-local, no actor field | `actor=` on gate rows |
| no identity/allocation on the board | `Owner` column on board rows; push-early spec-stub branch IS the reservation |
| enforcement is client-side hooks (a bare `git push` bypasses) | ship emits the run-table onto the BRANCH as attestation; a consumer CI action re-checks in-branch evidence (branch protection is the real block; hooks become UX) |

Git stays the ONLY shared medium (ADR-0022's L5 fence: no lock servers, no synced
state , merge semantics = conflict resolution). **Tripwire to unpark: a named second
user on a real repo** (lead + contractor is the kit's stated design intent). As of
2026-07-05 the tripwire has NOT fired, so team-mode stays parked. This note's only
team action: **reserve a `[modules] team_mode = false` slot** in Decision B's manifest
(a not-yet-installable add-on) and NAME team-mode in the refreshed philosophy doc
(Decision D) as a first-class future module, so the adoption story is honest about it
without building it early.

## Decision D , philosophy / README / onboarding refresh (capstone)

Once A (standalone subsystem commands), B (install/wire + manifest), and the kit-foldin
absorptions land, the kit's adoption model has changed, so the docs must catch up.
Sequenced LAST because it describes what the others built.

- **PHILOSOPHY:** add the composable-middle-level framing (bash-first + shallow-and-wide
  as a stated choice; a TOOLBOX you install a-la-carte, NOT an appliance you switch on;
  essential spine vs opt-in modules as the adoption model; git-as-only-shared-medium as
  the team stance; team-mode named as parked-not-absent). Keep it a philosophy, not a
  feature list. Explicitly state the anti-goal: the kit must never feel like one big
  product you adopt whole.
- **README:** lead with the standalone `<subsystem>` commands + the "install the spine,
  opt into modules" model + a one-command core install. The current README is written for
  one user who knows where everything is; rewrite for a first-time adopter who wants ONLY
  the SDD spine and should be able to stop there.
- **Onboarding (`install.sh` + `/kit:adopt`):** install becomes LAYERED , core spine
  unconditionally, then opt-in add-ons (`--with board,stats` or an interactive
  pick), recording the choice in the `[modules]` manifest. It never wires everything by
  default. `/kit:adopt` writes the manifest with spine-only defaults. This is where
  Decision B's optional tiering earns its keep, if at all.
- **`AGENTS.md` + `WORKFLOW.md` (the operate-contract, in the dwarves-kit repo):** these
  two describe the ORCHESTRATION LAYER (what to read first, the lanes, the gate at each
  phase boundary, how the pieces compose). After A/B/E change the command surface (standalone
  `<subsystem>` commands, `stats`, install/wire, the retired `lib`-vs-`tools`), both files
  reference stale names/flows. Refresh them to the new surface as part of this capstone ,
  they are the FIRST thing an adopting agent reads, so a stale operate-contract silently
  mis-drives every downstream run. (Han flagged these live in the OTHER repo, dwarves-kit,
  not ops-toolkit , so this deliverable is a dwarves-kit-side change, tracked here.)

## Decision E , the ledger / `stats` plane split (event-sourcing)

Han's question (2026-07-05): the "extract logs/run-reports/session-logs into different
kinds of ledgers" machinery , is it LEDGER-object-centric or MONITORING/feedback-loop-
function-centric? Answer: it is a false either/or. The shape is **event-sourcing (a log +
projections)**, which refuses to pick: the durable OBJECT is an append-only log, the
FUNCTIONS are projections over it. Two planes, one-way arrow:

```
  WRITE plane (the ledger = nouns)        READ plane (`stats` = verbs)
  append-only, source of truth            stateless, recomputable
  gate/proof/session events, transcripts  --one-way-->  yield, durations, correlations,
  (center of GRAVITY)                                   anomalies, scorecards, digests
        ^                                               (center of ACTIVITY)
        └────────── feedback loop: projection -> signal -> action -> new events
```

- **The ledger is the noun + center of gravity:** a few append-only event streams,
  write-once, never mutated, the audit anchor. Everything else derives from it.
- **`stats` is the verb + center of activity:** pure projections, NO durable state;
  re-running re-derives from the ledger. (The read-side is ONE human command over the
  monitoring/observability domain; the write side is harness-internal , execute/ship/gate
  append events as they run, not a command you type.)
- **The feedback loop is the function chain** that closes it (projection -> signal ->
  human/agent action -> new events) , activity OVER the two planes, not a third data thing.
- **The one load-bearing discipline:** a derived ledger is a PROJECTION, never a second
  source of truth. The "different kinds of ledgers" you extract are VIEWS, recomputable
  from the log, not new durable ledgers. The moment a projection is written back and
  becomes authoritative, you have two sources that drift , the exact class of bug the
  board-mirror had to fight (row-hash git-wins, refuse-all-on-missing-snapshot). Event-
  sourcing kills it by construction. Test: "can I replay a mega from six months ago by
  re-running the analysis over the log?" If yes, the log is the substrate and monitoring
  is the function , log-first, not loop-first.

This already exists physically by accident (`gate-ledger.sh` write-side in `lib/gate/`,
`ledger-observatory` read-side in `tools/`). Decision E only NAMES it and enforces the
one-way dependency + no-persisted-projection rule. Three consequences Han raised:

- **E1 , naming convention (rename):** write-side carries `-ledger` (`gate-ledger`,
  `proof-ledger`, `learned-ledger`); read-side NEVER does. So **rename `ledger-observatory`
  -> `stats`** (Han's pick 2026-07-05, over `obs`/`metrics`/`monitor`/`lens`: `stats` is
  short + honest + doesn't overpromise real-time like `monitor` or a time-series pipeline
  like `metrics`). A projection engine with "ledger" in its name lies about its plane. The
  human command is `stats <lens>` (`stats gate-yield|durations|deviation-rate|correlation|
  anomalies|scorecard`). SCOPE: `stats` owns the analytical lenses + the scorecard;
  **RUN_REPORT stays the mega flow's own closing verb**, NOT a `stats` subcommand , that is
  what keeps `stats` (a numbers-flavored name) from underselling a rendered narrative report.
  `lane-telemetry` is write-plane (emits) , keep or fold into the ledger substrate.
  Optional new abstraction (the ONE earned here): a **`ledger/` append substrate** , one
  `append` + `read` + location/schema handling that `gate`/`proof`/`session` writers all
  call instead of re-implementing row-append. Earned by 3+ streams; it is where E2 lives.
- **E2 , the event-store location IS configurable, write-plane + essential-tier.** One
  canonical `KIT_LEDGER_DIR` (aligning the existing `DWARVES_KIT_LOG_DIR`) via the
  `--repo-root`/`_repo_root()` seam; the write primitive writes there, `stats`
  reads the SAME root. NOT an optional toggle (the spine must have somewhere to write) ,
  it is essential config, not a `[modules]` feature. Two hard rules: (1) tests point it at
  `mktemp` (worker-hygiene); (2) ONE consumer = ONE ledger root, never per-stream-
  configurable, or `stats` can't join gate+proof+session and the source of truth
  re-fragments.
- **E3 , this retires the `lib/` vs `tools/` split (Han: "they're the same").** The split
  is packaging-accident, not architecture: `tools/` entries happen to carry own tests/docs/
  pyproject, `lib/` are flat call-by-path scripts , but `board` (lib/) is human-invoked +
  substantial and `ledger-observatory` (tools/) is too; the line leaks. "tool" vs "lib" describes
  a module's SURFACE (leaf/human-facing vs internal-helper), not its LOCATION. Target: every
  non-loader-mandated unit is a SELF-CONTAINED SUBSYSTEM MODULE (helpers + standalone entry +
  tests + docs co-located) under ONE tree; `tools/` retired as a separate concept. Constraint
  (unchanged, kit-foldin Decision 2): `agents/`, `commands/`, `hooks/`, `skills/` stay
  top-level (loader-mandated). This IS the modularity structure pass, so it lands HERE; kit-
  foldin's `tools/` placements are PROVISIONAL and this mega collapses them (cheap within-repo
  `git mv`). Exact top-level dir name (keep `lib/`, or a neutral `modules/`) is deferred to
  the mega , renaming `lib/` touches every `bash lib/...` call-site, so bias toward keeping it.
  **NO ALIAS SHIMS (Han directive 2026-07-05, added after grounding on the real merged state):**
  kit-foldin made the subsystem dirs but left ~34 SYMLINK ALIASES at `lib/` root (`lib/board.sh
  -> board/board.sh` etc.) so call-sites did not change. Han rejects scattered aliases. SG-01
  does the PROPER restructure , remove every lib-root alias and update every call-site to the
  real subsystem path via ONE `LIB_ROOT` anchor (`$LIB_ROOT/<subsystem>/<file>.sh`), no per-file
  wrapper/dispatcher (that is aliases renamed). This makes SG-01 a HIGH-blast-radius call-site
  refactor (opus, over-tested), gated by `find lib -maxdepth 1 -type l` EMPTY + full suite +
  orchestrate/mega-merge run e2e , the deliberate cost of a clean tree over cheap shims.

## Decision F , the module completeness bar (docs + wired, no orphans)

Han's requirement (2026-07-05): after this lands, every IMPORTANT component must (1) have
its own usage doc and (2) be wired into the workflow. Reframed as a DEFINITION OF DONE for
a module , a module is not "done" until BOTH hold, and neither is optional:

- **(1) Usage doc per important module.** Each subsystem/module (`board`, `stats`, `gate`,
  `session`, `queue`, `spec`, ...) ships a short usage doc , what it does, the `<subsystem>
  <verb>` surface, its config knobs (which `[modules]` toggle / env), one worked example.
  Co-located with the module (the modularity/self-contained rule from E3: docs live IN the
  module dir), NOT a central manual. Calibrate to the `ops-tool-docs` shape , real usage,
  not template fill. "Important" = anything a consumer installs or a lane fires; internal
  one-off helpers do not each need a manual.
- **(2) Wired into a workflow firing point.** A standalone-but-dormant module is half-done ,
  it must have a real trigger: a lane that calls it, a `/kit:*` command, a hook event, or a
  documented cron/human entry. This is the SAME gap the parked ID-273 "kit-wiring" audit
  found (only 13/30 commands + 9/24 agents actually fire; root cause = the lane bypass). So
  Decision F ADOPTS ID-273's firing-point discipline as the bar: for each module, name WHERE
  it fires; if nothing fires it, that is a finding (either wire it or justify it as
  human/cron-only). Do NOT ship a module the workflow never reaches.

This is a per-module GATE, checked at the module's own sub-goal, not a separate docs phase ,
so a module's PR carries its usage doc + its firing point or it is not done.

## Decision G , reconcile the three scaffolding surfaces (never-diverge)

Han's requirement: once the orchestration layer is updated (A/B/E + the AGENTS/WORKFLOW
refresh in D), CROSS-CHECK the three goal-scaffolding surfaces so they describe the SAME
orchestration and reference no stale names/paths:

- **`plan-for-goal`** (skill) , the single-goal scaffolder.
- **`plan-for-mega-goal`** (skill) , the mega scaffolder.
- **`/kit:mega`** (kit command) , the kit-native mega projection.

They already carry a **never-diverge contract** (runner-fastpath SG-01/02 synced the triage
ladder across the skill and `/kit:mega` in one run, with a byte-identical block + a checklist
row). Decision G extends that: after the rename/restructure, every reference these three make
to kit internals , `orchestrate`/`queue`, `board`, `gate-ledger`, `ledger-observatory` (now
`stats`), `lib/<x>.sh` paths, the install/wire model , must be updated in lockstep, and the
mirror check re-run so the skill and `/kit:mega` still agree. This is the CAPSTONE
verification of the mega (after D), because it can only be done once the surface it reconciles
against is final. Deliverable: a diff across all three + a re-asserted mirror check, not just
"looks consistent".

## Decision H , wire backlog + megagoal + learning-ledger into the personal Hermes agent (Air) , THE PAYOFF

Han's emphasis (2026-07-05): the MOST special part of this whole line of work. The three
durable stores surface INTO the Hermes agent on the **Mac Air** (his daily driver), so the
entire ops cockpit is steerable from the agent he actually talks to, and his moves flow back.
This is the concrete terminus of Decision E's feedback loop , the read-side reaching the human.

- **Three sources wired into Hermes:**
  1. **backlog** , the kanban cockpit (already built: the kit board `mirror`/`writeback`
     git<->Hermes bridge from runner-fastpath SG-07/08).
  2. **megagoal** , active mega-goal state + progress as cards (board-mirror already mirrors
     "active mega-goals"; extend to richer per-sub-goal state / the ROADMAP box state).
  3. **ledger (LEARNING)** , the learning-ledger stream (the accumulate-mode learned-ledger,
     i.e. the session/learning events in Decision E's write plane) surfaced as cards/notes,
     so settled knowledge is visible + actionable in the agent, not buried in a file.
- **Mechanism = extend the EXISTING bridge, don't invent one.** The kit board `mirror`/
  `writeback` is the generic engine (kit). Decision H adds (a) two more SOURCES (megagoal
  state, learning-ledger) to the mirror, and (b) makes the TARGET the Air's Hermes , which is
  consumer/personal config per engine-in-kit/data-in-ops, NOT a new kit hardcode.
- **Discipline carries (load-bearing, from SG-08):** git stays the SoT; one-writer-per-
  direction; row-hash conflict -> git wins; a missing snapshot -> REFUSE ALL (never apply-
  everything); every Hermes-visible field sanitized + untrusted-tagged (SG-08's #182 fix).
  The learning-ledger surfaces read-only by default (a learning is a record, not a kanban row);
  writeback stays scoped to the backlog/megagoal planes unless Han wants to curate learnings in
  Hermes too.
- **OPEN , the target Hermes topology (resolve at draft).** The runner-fastpath bridge demo
  targeted the MINI's `foundation.d.hermes-agent` (16 cards on the Mini). Han now names the
  **Air**. So the key deployment decision: is this a RETARGET to a Hermes on the Air (the Air
  already runs `ai.hermes.gateway`), a SECOND personal Air agent distinct from the Dwarves-
  tenant Mini agent, or the Air routing THROUGH to the Mini? This is personal-infra + minimum-
  infra-first (SSH/existing-gateway before a new daemon). Verify the Air's actual Hermes setup
  before drafting , do not assume a new agent.
- **Scope call:** this is deployment + a bridge-SCOPE extension , heavier and higher-value than
  the A-G structure work. It may warrant being ITS OWN focused mega (the "personal Hermes
  cockpit"), sequenced WITH or AFTER kit-modularity rather than a sub-goal buried inside it.
  Flag for Han at draft time.

## Proposed decomposition (the sub-goals these decisions become, when the mega drafts)

SCAFFOLDED 2026-07-05 (Han directed full-scaffold ahead of the precondition) at
`_meta/megagoals/kit-modularity/` , 7 sub-goals, BLOCKED on kit-foldin (ID-276) shipping first
(don't-pre-scaffold-successors: 03 needs SG-01's real subsystem dirs, 07 the final surface , so
03/07 may need a touch-up once kit-foldin merges). The scaffold's ROADMAP is now authoritative;
this table is the summary. TWO megas fall out (H is its own, NOT scaffolded):

**kit-modularity mega** (A-G; F is a per-module GATE, not a sub-goal; C folds into 04+06):

| SG | What (decision) | Depends | Tag |
|---|---|---|---|
| 01 module-collapse | retire `lib`-vs-`tools` into self-contained subsystem modules (E3) , structural, over-test | , | auto |
| 02 stats-plane | rename `ledger-observatory`->`stats` + extract `lib/ledger/` append substrate + `KIT_LEDGER_DIR` (E) | 01 | auto |
| 03 subsystem-commands | per-subsystem `<sub> <verb>` standalone entries + optional thin `kit` dispatcher (A) | 02 | auto |
| 04 install-wire | layered install + `[modules]` manifest + `team_mode` slot (B+C) | 03 | auto |
| 05 operate-contract | refresh dwarves-kit `AGENTS.md` + `WORKFLOW.md` to the new surface (D-part) | 01-04 | auto |
| 06 docs | philosophy (toolbox-not-appliance) + README + onboarding + per-module usage-doc rollup (D) | 01-04 | auto |
| 07 reconcile | `plan-for-goal` / `plan-for-mega-goal` / `/kit:mega` lockstep + re-run mirror check (G) , LAST | 01-06 | gate (never-diverge is taste-adjacent) |

F (module completeness bar) is baked into 01/02/03: each module's PR carries its usage doc +
firing point, or the sub-goal is not done. Not a standalone SG.

**Hermes-cockpit mega** (H , its OWN mega, deployment-heavy, AFTER kit-modularity):

| SG | What | Tag |
|---|---|---|
| H-01 megagoal source | extend the SG-07/08 board-mirror to surface active mega state/progress as cards | auto |
| H-02 learning source | extend the mirror to surface the learning-ledger (read-only by default) | auto |
| H-03 Air target | resolve the topology (Air `ai.hermes.gateway` vs Mini agent vs a new personal Air agent) + configurable target | auto |
| H-04 deploy | wire on the Air (runbook, minimum-infra: caffeinate/launchd per runner-fastpath SG-06 precedent) | gate (deploy) |

Writeback discipline (git-wins, refuse-all-on-missing-snapshot, untrusted-sanitize) carries
from SG-08 unchanged.

## Sequencing + what's NOT decided here

- **Order:** kit-foldin FIRST (it delivers the subsystem dirs A needs + the final
  module set B wires). THEN a "kit-modularity" mega (the middle-level adoption model, NOT
  a product-consolidation): A (standalone subsystem commands) + B (install/wire + manifest)
  + E (ledger/`stats` plane split: rename `ledger-observatory`->`stats`, the
  `ledger/` append substrate + `KIT_LEDGER_DIR`, retire `lib/`-vs-`tools/`) can be
  parallel-ish; **F (module completeness bar: usage doc + firing point) is NOT a phase but a
  per-module GATE baked into every A/B/E sub-goal** (a module's PR carries its doc + wiring or
  it is not done); D (docs/onboarding + the AGENTS.md/WORKFLOW.md operate-contract refresh) is
  the capstone after all; **G (reconcile plan-for-goal / plan-for-mega-goal / /kit:mega + re-run
  the mirror check) is the FINAL step after D**, since it reconciles against the now-final
  surface. C is one manifest slot + one philosophy paragraph inside D, not its own sub-goal.
  E's `tools/`-collapse touches
  the same tree as A's subsystem entries , sequence E's structure move BEFORE or WITH A.
  **H (the personal Hermes cockpit , wire backlog + megagoal + learning-ledger into the Air's
  Hermes) is the PAYOFF and likely its OWN focused mega**, sequenced WITH or AFTER kit-modularity
  (it needs the `stats`/ledger surface + the module set stable, but it is deployment + bridge-
  scope, not structure , so it does not belong buried in the A-G structure mega).
- **Not decided:** the mega's exact sub-goal split; whether the optional `kit` discovery
  dispatcher is worth building at all (standalone commands are the surface regardless);
  two-tier vs three-tier optionals; whether `/kit:adopt` gains an interactive module-picker
  or just writes spine-only defaults; the exact `[modules]` manifest schema; per-module
  install granularity (`install.sh --with` flags vs per-module `install` scripts). Those
  resolve when the mega is drafted , once kit-foldin ships, same design-first discipline.
