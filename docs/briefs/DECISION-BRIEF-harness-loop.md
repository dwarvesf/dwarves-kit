# DECISION BRIEF: harness-loop, closing Specify → Execute → Observe → Govern → Learn

**Status:** DRAFT (for Han's review; drafted 2026-07-12 from a 3-agent mechanism audit)
**Scope:** dwarves-kit (engine) + thin consumer-side deploy legs (ops-toolkit LaunchAgent, per session-intel precedent)
**Prior art this composes (does not re-litigate):**
`docs/research/2026-07-05-harness-ops-loop-and-naming.md` (the five-leg loop, canonized),
`docs/research/2026-07-05-auto-improvement-loop-design.md` (ledger → proposals + review dashboard),
`docs/research/2026-07-02-process-effectiveness-audit.md` (R1-R11: what gets read vs write-only),
ADR-0031 (understanding gate; no new learning engine in the kit), SPEC-126 (weekend-batch split),
SPEC-182/183/184/188/192 (stats plane + config layer), ADR-0009 (plugin dual-ship), ADR-0024 (spine).

---

## 1. Problem

The loop is built on four legs and open on the fifth. Today:

```
Specify ──► Execute ──► Observe ──► Govern ──► Learn ──┐
   ▲            strong      built,     strongest  OPEN │
   │ strong                 unread                      │
   └──────────── feedback never closes ─────────────────┘
```

Every Observe artifact exists (append-only run ledgers, the read-only `stats`
DuckDB projection with `digest` / `anomalies` / `gate-yield` / `lane-telemetry`),
but **nothing triggers a read**. Every Learn artifact exists (harvest, backlog-stage,
weekend-batch, add-backlog), but **every hop is a human hop**, and the humans are
starved:

| Evidence (measured 2026-07-12) | Meaning |
|---|---|
| 69 `## [staged]` candidates in `_meta/backlog-staging.md`, oldest 2026-06-29 | staging works, promotion is the bottleneck |
| ~140 `queued` rows in `learned-ledger.md`, exactly 1 ever `flushed:` | the knowledge ledger is a write-only diary (the exact R4/R6 anti-pattern) |
| `mega-durations` / digest time-to-done ≈ empty on the live corpus | OUTCOME timing brackets wired at almost no gate call sites |
| kit-retro goal drafted 2026-07-05 (`ops-toolkit/_meta/megagoals/kit-wiring/goals/kit-retro.md`), never run | the DECIDED Learn-leg closure was never wired |
| queue has zero recurrence concept (`lib/queue`: no cron/standing/recurring) | the decided "recurring retro in the overnight queue" is not representable |
| README agents table lists 11 of 25; no Observe/Learn narrative; stale "v2 roadmap: SessionEnd knowledge capture" bullet | the front door does not tell the loop story |
| ~30 runtime env knobs, ~7 documented; no view/edit surface over the shipped config resolver | config layer shipped (SPEC-183/192) but is invisible |
| No wizard anywhere; plugin path has no module gating at all (`install.sh:340`) | first-run experience is flags-and-README |

Six named break points from the mechanism audit (referenced below as BREAK A-F):

- **A** run-completion never triggers distillation (retro/stats are human-invoked)
- **B** knowledge store (`learned-ledger.md`) and work store (`backlog-staging.md`) never bridge
- **C** run-ledger anomalies reach staging only via on-demand `stats anomalies --propose`
- **D** promotion is a single manual `add-backlog` gate; staged rows never age or expire
- **E** debt paydown depends on Han remembering the weekend skill
- **F** OUTCOME emitter missing at most gate sites, so north-star metrics are honest-zero

## 2. Design stance (constraints we keep)

1. **Propose, don't dispose.** Every automated leg ends at a staging file or a
   rendered surface; `add-backlog` and mega sign-off stay human. (kit-foldin DECISIONS, ADR-0031)
2. **A Learn artifact must have a real reader or be a forcing function** (audit R4/R5/R6).
   We add exactly one new reader (the retro cycle) and one forcing function (the sign-off
   dashboard); we add zero new diaries.
3. **No recurrence engine in the kit.** PHILOSOPHY §3 declines unbounded outer loops;
   scheduling stays external (LaunchAgent, session-intel precedent). Recurrence in the
   queue = date-suffixed slug (`kit-retro-2026-W29`), zero queue changes.
4. **Hooks never read config** (SPEC-183 lint). The wizard and config surface are
   commands, not hooks.
5. **No new learning engine in the kit** (ADR-0031): the LLM distill step reuses the
   operator's absorb-ideas skill via the drafted kit-retro goal; the kit ships only the
   deterministic aggregate + propose plumbing.

## 3. Solution: three workstreams

### WS-1 · Learn-leg closure (the open seam; do first)

```
                        ┌── deterministic ──────────────────────────┐
 run ledgers ──► stats digest --propose ─┐                          │
 (gate/DEBT/TOKENS)     anomalies        ├──► _meta/backlog-staging.md ──► add-backlog ──► BACKLOG.md
                                         │        (## [staged], evidence-cited)   (human, unchanged)
 NOTES ## Proposed-additions ─┐          │
 learned-ledger queued rows ──┤ kit-retro goal (LLM, absorb-ideas skill,
 observatory lenses ──────────┘ weekly queue row kit-retro-YYYY-WW)
```

- **1a. Land PR #226** (harvest dedup flock). Already open; merge, done.
- **1b. Wire the kit-retro goal** (the drafted contract, verbatim): stage it as a
  date-suffixed queue row weekly (consumer LaunchAgent appends the row + fires
  `queue.sh run`, or it rides the existing overnight launch). Its first live run is the
  proof. Closes BREAK A for the LLM path. The date-suffix convention is the whole
  "recurrence" feature: journal dedup already handles the rest.
- **1c. `stats propose` hardening**: promote `anomalies --propose` + a digest-derived
  propose into the retro cycle's deterministic leg; every proposal cites lens + figure +
  rids (the auto-improvement doc's three disciplines: propose-only, cite-the-number,
  dedup against open AND rejected). Closes BREAK C. Flip `[features] auto_improvement`
  to `[impl]` and amend the SPEC-188 inert-key lint in the same PR.
- **1d. Staging drain + aging**: `add-backlog review` gains a grouped, age-sorted,
  evidence-first render (the 5-minute drain ritual), and staged rows older than N days
  auto-archive to a `[expired]` section with a one-line count in the next retro cycle
  (never silently deleted). Closes BREAK D's starvation without touching the human gate.
- **1e. Knowledge→work bridge (minimal)**: the retro cycle reads `learned-ledger.md`
  queued rows ONLY to count + surface them ("140 queued, 1 flushed, oldest 28d") in its
  staged output; flushing stays the learning-ledger skill's job. BREAK B is bridged by
  visibility, not by a second engine. BREAK E same treatment: the retro cycle surfaces
  the `weekend-batch list` count so unpaid debt shows up weekly without a new closer.

### WS-2 · Observe presentation (make the loop's output legible)

- **2a. OUTCOME emitter completion**: wire the timing brackets at the missing gate call
  sites (small diff, mostly `commands/*.md` + orchestrate emit points). Unblocks
  `mega-durations` + digest time-to-done. Closes BREAK F. Do early; every later metric
  reads better.
- **2b. Per-mega review dashboard as the sign-off surface**: at TIER-4 close, compose
  the already-shipped `stats render --surface artifact` formatters into one HTML file
  per mega (gate table, proof links, PR/CI states, token cost, coverage deltas,
  grouped per sub-goal, attention-colored). It becomes what Han eyeballs before the
  gated-final click, a forcing function with a guaranteed reader. (Companion design in
  the auto-improvement doc, "review mechanism" table.)
- **2c. Scheduled weekly digest**: fold `stats digest` output into the existing
  session-intel weekly LaunchAgent file (one dated intel file gains a "harness
  scorecard" section). No new daemon.

### WS-3 · Front door (onboard, config, README)

- **3a. `bin/config` (list / get / explain)**: read-only first. Renders every declared
  key with: effective value, provenance (env > project `.kit.toml` > kit-root > default),
  status tag (`[impl]/[design]/[reserved]/[consumer]`, rendered visibly inert when not
  impl), and owning module + enabled state. Backed by a checked-in env↔key registry
  (the ~30-var sweep becomes ONE table file, linted like `KIT_KNOWN_MODULES`, so docs
  cannot drift again). `config set` (writes project `.kit.toml` only) ships after the
  read verbs prove out.
- **3b. `/kit:onboard` wizard (command, not install-script prompts)**: detect install
  mode (plugin / bash / none / both-with-double-hooks), offer `/kit:adopt` for the cwd
  repo, pick modules interactively (bridging the plugin path's missing `--with`),
  capture the consumer knobs that make chosen modules non-inert (MONEY_GATE_REPOS,
  PROSE_RAG_CORPUS+INJECT, ledger location) into `.kit.toml` + printed env guidance,
  disclose plugin-path gaps (statusLine, frozen SHA), end with the welcome tour +
  first-cycle pointer. Pure orchestration over install.sh / adopt.sh / kit-config.sh;
  confirms before every write.
- **3c. README/docs truth pass, LAST**: agents 11→25, skills 1→2, strike the stale
  "v2 roadmap: SessionEnd capture" bullet, fix architecture.md's "25+15=40" headline,
  and add the five-leg loop as the README's organizing narrative (promote the
  2026-07-05 research framing to the front door, each module mapped to its leg,
  Observe/Learn finally visible). Also: capture the missing retro for the modularity
  cycle (docs/retro has nothing after 2026-07-04).

### 3.4 The circuit after the loop closes (what "improvement flow" means here)

```
        ┌────────────────────────────────────────────────────────────────┐
        │                                                                │
  run ──► ledgers ──► weekly `learn propose` ──► staging ──► Han promotes│
  (any    (gate/DEBT/   (cited, deduped,          (drain     (board row) │
  lane)   TOKENS/       adversarially checked)     ritual)        │      │
        │ OUTCOME)                                                ▼      │
        │                                            ordinary assign →   │
        └──────────────────── ships, emits ◄──────── lane → gates → ship─┘
```

A promoted proposal is an ORDINARY board row; no special executor exists or is
wanted. Harness-targeted rows land on the dwarves-kit board and drain through the
same overnight queue as feature work. Three targets, three channels, all already
built: PROCESS improvements (gate-yield's ceremony detector can propose removing or
tuning a gate, so the loop prunes its own ceremony, the 2026-07-02 audit's
disposition contract generalized); HARNESS/CODE improvements (the normal SDD lane);
SKILL improvements (signals route to the existing skill-curator channel, which owns
skill proposals, shared propose+dedup discipline, different target). Memory
staleness has a named owner OUTSIDE this mega (ID-100 context-lifecycle, queued);
until it ships, the weekly cycle runs `stats memory-sweep` and surfaces staleness
counts as cited signals (tripwire, not repair).

## 4. Naming, scope, modularity (the load-bearing risk, locked FIRST)

Han's flag 2026-07-12: naming + scope + modularity are the huge issue. So the mega's
first sub-goal is a **gated taxonomy ADR** that locks all of the below before any build
PR opens. Working positions for that ADR (to be attacked, not assumed):

**4.1 A new `learn` subsystem, the Learn leg's one home.** Today Learn machinery is
scattered: `weekend-batch.sh` sits in `lib/queue/` (an Execute dir), harvest rides the
`session` module, backlog-stage rides `board`. Position:
- `lib/learn/` + stable `bin/learn` entry (`<subsystem> <verb>` shape, SPEC-184):
  `learn propose` (the cross-run distiller), `learn drain` (staging review render),
  `learn debt <list|collect|mark-paid>` (weekend-batch relocated).
- Physical move `lib/queue/weekend-batch.sh` → `lib/learn/`, **no alias shims**
  (kit-modularity precedent: update every call-site via the stable bin path). The
  dotfiles `weekend-debt-paydown` skill currently deep-calls
  `lib/queue/weekend-batch.sh`, itself a SPEC-184 violation; the repoint to
  `bin/learn debt` fixes it. Cross-repo edit, one release, no back-compat layer.
- Hooks stay where they fire (harvest/backlog-stage remain SessionEnd hooks in their
  modules); the subsystem owns the READ/propose side, not the capture side.

**4.2 Retro naming collision, disambiguated by subsystem.** `/kit:retro` (per-run,
human Q&A) keeps its name and job. The cross-run distiller is **never called retro**:
it is `learn propose` at the lib layer, and the recurring queue goal keeps its drafted
name `kit-retro-YYYY-WW` (date-suffix = the whole recurrence mechanism). The ADR
records the rule: one word, one meaning; `retro` = per-run reflection, `propose` =
cross-run distillation.

**4.3 Legs are metadata, modules stay install units.** No wholesale module renames
(install records + `KIT_KNOWN_MODULES` compat). Instead each module/subsystem declares
a **primary leg** in one checked-in registry table (rendered by README and `config
list`), acknowledging the two honest spanners (board: Specify input + Learn output;
session: Observe capture + Learn capture). The five-leg frame becomes the front door's
organizing narrative without churning the install surface.

**4.4 Front-door verb fences.** Three commands, three jobs, locked in the ADR:
`/kit:start` = state detector (never writes), `/kit:adopt` = mechanical contract
injector (idempotent, never interactive), `/kit:onboard` = the interactive first-run
orchestrator that CALLS both. `bin/config` is the read/explain surface over the
SPEC-183 resolver; the resolver file `lib/config/kit-config.sh` stays the only reader
of TOML.

**4.5 Scope fences (kit-fold contract).** Engine in the kit, consumer state via
repo-root anchoring only: the weekly LaunchAgent, boards.txt, Hermes cockpit legs stay
consumer-side; no tenant paths kit-side; `learn propose`'s consumer inputs
(`learned-ledger.md`, staging file) resolve via the existing env/`--repo-root`
channels the stats adapters already use. One engine, one truth: the drafted kit-retro
goal file moves INTO this mega and out of kit-wiring (no duplicate owners).

**4.6 Naming-convention deltas.** The 2026-07-05 role-suffix vocabulary gains one
entry, `-propose` (a propose-only writer whose ONLY legal sink is a staging file),
formalizing the discipline the auto-improvement design states in prose.

**4.7 bin/ consolidation (Han's flag 2026-07-12: "these bin are fragmented").**
Today's `bin/` has 11 entries in three mixed grammars: five `session-*` siblings,
a verb-first `add-backlog` orphaned from its board family, module CLIs beside
subsystem entries, and NO entries for spec/goal/stats/mega/queue. Position: ONE
grammar, `bin/<subsystem> <verb>`, one entry per subsystem: the five `session-*`
CLIs collapse into `session observe|intel|recall|report|semantic`; `add-backlog`
folds as `board promote` (the 2026-07-05 naming doc's own deferred open question,
now decided; verb-first survives only as the human-typed alias IF the ADR keeps
one); missing subsystem entries (spec, goal, stats, mega, queue) get created so
the surface is COMPLETE, not just tidy. Module CLIs (`prose-rag`,
`worktree-provision`) keep their module names (they are opt-in modules, not
subsystems); the ADR states this two-class rule explicitly. No alias shims
(kit-modularity precedent); consumers repoint (vps-mon heartbeat, the
session-observe skill, LaunchAgents, install.sh CLI wiring).

**4.8 skills/ gets a rule, not just more files.** 2 top-level skills + 1 hidden at
`lib/stats/skill/`. Position: the ADR states what earns a kit skill (a workflow an
AGENT should auto-fire on that drives kit machinery, per the PHILOSOPHY skill-routing
rule: loop machinery kit-side, reflex skills operator-side), relocates the stats
skill to `skills/` (or records why it stays subsystem-internal), and the README
stops under-selling the surface. Thin is acceptable; undecided is not.

**4.9 One scheduler, not plist-per-job (Han's flag: "daemon installation are
fragmented").** Today each scheduled job ships its own LaunchAgent. Position: the
kit ships ONE scheduler template, a single weekly LaunchAgent that runs a small
dispatcher reading a declarative jobs list (session-intel digest, kit-retro
staging, future entries), one plist, one runbook, one place to see what runs and
when; per-job plists retire. Minimum-infra: adding a weekly job becomes a jobs-list
line, not a new daemon. BTM rules apply to the one launcher. Consumer instantiates
it (SPEC-126 split unchanged); the kit owns the template + dispatcher.

## 5. Packaging and sequencing

One mega-goal, `harness-loop`, in `dwarves-kit/_meta/megagoals/harness-loop/`
(kit-adopted, SDD lane, gh-sequential, gated-final):

| # | Sub-goal | Lane | Depends | Notes |
|---|---|---|---|---|
| 01 | loop-taxonomy-adr (§4) | full, **gate** | , | the naming/scope/modularity ADR; nothing builds until Han approves it |
| 02 | outcome-emit-sweep (2a) | normal | , | small diff, unblocks metrics; NC: a gate with no bracket renders honest-empty |
| 03 | harvest-dedup-land (1a) | tiny | , | merge PR #226 |
| 04 | learn-subsystem (4.1) | normal | 01 | lib/learn scaffold + weekend-batch move + all call-site repoints (incl. dotfiles skill, cross-repo) |
| 05 | retro-cycle (1b+1c+1e) | full | 01,02,04 | the Learn keystone: `learn propose` + kit-retro goal wiring + adversarial proposal check; flips `[features] auto_improvement` + SPEC-188 lint; proof = one live run staging ≥0 cited candidates + honest-empty NC |
| 06 | staging-drain (1d) | normal | 01,04 | `learn drain` render + 30d aging policy |
| 07 | mega-review-dashboard (2b) | normal | 02 | composes shipped render formatters; wired at TIER-4 close as the sign-off surface |
| 08 | config-surface (3a) | normal | 01 | `bin/config` read verbs + the env↔key registry + drift lint |
| 09 | onboard-wizard (3b) | full, **gate** | 08 | `/kit:onboard`; gated (UX taste, Han reviews) |
| 10 | front-door-truth (3c) + weekly-digest fold (2c) | normal | 05,07 | docs LAST, documents what shipped; consumer LaunchAgent leg rides here |

**Resolved decisions (Han delegated 2026-07-12, "prefer thorough"):**

1. **Retro cadence:** weekly consumer-side LaunchAgent stages `kit-retro-YYYY-WW` and
   fires `queue.sh run`, plus an on-demand `learn propose` verb. NOT coupled to queue
   night-end (keeps the launcher dumb; a missed week self-heals next week).
2. **Interpret stage:** one sonnet pass, then a claim-verifier-style adversarial check
   per proposal (refute-if-uncertain drops it) before staging. Two cheap passes beat
   one careful one; matches the kit's adversarial-verify DNA.
3. **Staging aging:** 30 days → moved to an `[expired]` section (never deleted); the
   weekly propose run surfaces the expired count so silence is visible.
4. **Wizard surface:** `/kit:onboard` command. `install.sh` stays non-interactive by
   design (batch scripts don't prompt; ADR-0009 paths unchanged).
5. **Proposal routing:** per-proposal `Home:` → the owning repo's board;
   engine-scoped proposals → the dwarves-kit board. No new central board (the
   `board-all` cockpit already aggregates).

Explicitly OUT of this mega:
- **kit-wiring (ID-273)** stays its own queued mega (firing points for the 17 dormant
  commands / 15 agents). ONE overlap resolved here: the kit-retro goal moves out of
  kit-wiring into this mega's 03 (it is the Learn keystone, not a generic wiring row).
- **team-mode (ID-278)**: unblocked (kit-modularity shipped) but sequenced after this
  mega; its pilot still needs a named second engineer.
- **ID-100 context-lifecycle**: adjacent to 3a/3b but a different owner (per-repo
  context stack, not harness config). Sequence after; 3a's provenance renderer is a
  building block it can reuse.
- Any auto-promotion, auto-flush, or kit-side scheduler: rejected by stance rules 1/3/5.

## 6. Status

- 2026-07-12: brief drafted from the 3-agent mechanism audit; Han reviewed v1,
  delegated the five open calls ("your call, prefer thorough") and flagged
  naming/scope/modularity as the primary risk → §4 added, taxonomy ADR promoted to
  gated sub-goal 01, decisions recorded in §5.
- Next: mega-goal scaffold at `_meta/megagoals/harness-loop/`, then SG-01 runs
  `/kit:think` → the taxonomy ADR.
