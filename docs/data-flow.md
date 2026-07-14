# Data flow

`docs/architecture.md` says what the pieces are. `docs/WORKFLOW.md` says how one RUN moves
through the phases. This page says how DATA moves: where a signal is born, what it becomes,
and how it closes back into the next run. It was the missing third view (a 2026-07-14 sweep
found 14 lifecycle diagrams and zero data-flow ones).

Three flows, one per substrate:

1. **The signal path** (Observe -> Learn -> Specify): telemetry becomes a proposal becomes work.
2. **The ledger path** (Execute -> Govern -> Observe): a run writes evidence; the gates and the
   lenses read it.
3. **The module map**: who calls whom, grouped by leg.

---

## 1. The signal path: telemetry -> proposal -> board -> ship

The Learn leg's whole job. Every arrow is code, not intent; the names are the callables.

```
  SOURCES                COLLECT + ANALYZE            PROPOSE              HUMAN         WORK
  ─────────              ─────────────────            ───────              ─────         ────

  run ledger  ─────┬──►  stats <lens>          ──┐
  logs/runs/*.log  │     (DuckDB, in-memory)     │
                   │                             │
                   ├──►  lane-telemetry report ──┤ (advisory only,
                   │     (bash/awk)              │  feeds /kit:retro)
                   │                             │
                   └──►  learn debt list       ──┤
                                                 │
                                                 ├──►  learn propose ──┐
                                                 │     (aggregate +    │
  CC transcripts ──┬──►  session observe      ──┤      LLM interpret  │
  ~/.claude/       │     (deterministic)         │      + adversarial  │
  projects/*.jsonl │                             │      refute)        │
                   ├──►  session semantic      ──┤                     │
                   │     (cheap LLM)             │                     ▼
                   │                             │            ┌──────────────────┐      ┌──────────┐
                   ├──►  session intel run     ──┤            │  _meta/backlog-  │      │  _meta/  │
                   │     (weekly digest)         │            │   staging.md     │      │ BACKLOG  │
                   │                             │            │                  │ ───► │   .md    │
                   └──►  session audit run     ──┤            │  ## [staged]     │      │          │
                         (agentic LLM,           │            │  - Intent:       │ board│ | ID-N | │
                          dated report,          │            │  - Approach:     │ prom.│          │
                          {PREV} metric diff)    │            │  - Tags:         │      └────┬─────┘
                              │                  │            │  - Source: <cite>│           │
                              └── triage ───────►│            └──────────────────┘           │
                                                 │                     ▲                     │
  repos / boards ──┬──►  stats anomalies      ──┘                     │                     │
                   │     --propose ─────────────────────────────────────┘                     │
                   │                                                                          │
                   └──►  skill-curator reviewer ──►  ~/.claude/skill-proposals/<slug>/         │
                         (per-session, hook)         (its own currency: a SKILL.md draft;      │
                                                      gate = skill-review promote)             │
                                                                                              ▼
                                                                                     /kit:spec ->
                                                                                     /kit:execute ->
                                                                                     /kit:ship
                                                                                              │
                                    the loop closes: the ship writes the ledger ◄─────────────┘
                                    (flow 2), which is what the next audit reads
```

**The four invariants of this flow** (SPEC-200), and why each is load-bearing:

| Invariant | In this diagram |
|---|---|
| **I1 one currency** | Every proposer lands in the SAME box: `## [staged]` blocks rendered by `lib/learn/staging-format.py`. `learn propose`, `stats --propose`, and `session audit triage` all write it. Nothing writes `BACKLOG.md` directly. |
| **I2 one env family** | That box's path is `BACKLOG_STAGE_STAGING` for every writer (was three different names). |
| **I3 one durable root** | Everything on the left resolves its paths through `kit_resolve_log_dir` (flow 2). |
| **I4 one verb** | `run` produces, `propose` stages, `promote` is the human gate. |

**The human gate is the only edge into `BACKLOG.md`.** `board promote` is a person's decision;
`learn drain` is how they review the pile (and ages stale blocks to `[expired]`). Propose-don't-
dispose: a machine may fill the staging buffer forever and never move the board.

**Two proposers are NOT yet on this path** (SPEC-200 T6/T7, open): `session intel`'s
synthesis/repeat proposals and `/kit:retro`'s action items emit prose inside their own report,
so a human must retype them to act. A lead nobody can promote is a lead nobody actions.

**One writer keeps a private copy of the grammar** (open debt): `hooks/backlog-stage.py` has its
own `render_candidate` instead of importing `lib/learn/staging-format.py`. It is byte-identical
today, which is exactly how it will drift tomorrow. Same for `lib/board/bin/add-backlog`'s
private `parse_staging`. Both are named in staging-format.py's own docstring as known
duplication; I1 is only half-enforced until they import the one module.

---

## 2. The ledger path: who writes evidence, who reads it

One append-only corpus, one resolver. Every path below is derived, never hardcoded (SPEC-097).

```
                        ┌────────────────────────────────────────────┐
   WRITERS              │   kit_resolve_log_dir()                    │      READERS
   (Execute + Govern)   │   lib/telemetry/kit-log-dir.sh             │      (Observe + Govern)
                        │                                            │
  gate-ledger.sh  ────► │   KIT_LEDGER_DIR                    (1)    │ ◄──── lane-telemetry
   START / GATE /       │   DWARVES_KIT_LOG_DIR   (alias)     (2)    │        report | misfires
   OUTCOME / TOKENS /   │   kit.toml [ledger].location        (3)    │        | render | trace
   DEBT rows            │   $XDG_STATE_HOME/dwarves-kit/logs  (4)    │
                        │                                            │ ◄──── stats  (kit_runs,
  proof-ledger.sh ────► │            │                               │        kit_gates tables;
   proof + override     │            ▼                               │        in-memory DuckDB,
                        │   <root>/runs/<rid>.log     (per run)      │        persists nothing)
  queue.sh        ────► │   <root>/completeness.log                  │
   journal (idempotency)│   <root>/queue-journal.tsv                 │ ◄──── learn debt list
                        └────────────────────────────────────────────┘        (| DEBT | rows)
                                          ▲                                ◄──── mega report /
                                          │                                       mega review
   hooks (ship-gate, safety-gate, ...) ───┘  ── read the SAME ledger to decide
                                              whether a push may proceed (Govern)

   NOT in the ledger, by design:
     ~/.claude/intel/{intel,audit}-YYYY-MM-DD.md   the Observe reports (dated artifacts)
     _meta/backlog-staging.md                      the proposal buffer (flow 1)
     ~/.claude/dwarves-kit/logs/*.log              hook diagnostics (ephemeral, not corpus)
```

Why one resolver matters: a plugin reinstall wipes `~/.claude/dwarves-kit/`. Anything that
defaults there loses its history. `queue.sh` did exactly that until 2026-07-14, and the queue
journal IS its idempotency state, so a wipe re-runs completed work. That is the whole reason
SPEC-097 exists and why C6 of the kit contract lints for it.

---

## 3. The module map, by leg

Who calls whom. An arrow is a real invocation (shell-out, source, or import).

```
   SPECIFY                    EXECUTE                    GOVERN
   ───────                    ───────                    ──────
   spec  ──► classify         queue ──► orchestrate      gate ──┬─► gate-ledger
     │         │                │         │                     ├─► proof-ledger
     ▼         ▼                ▼         ▼                     └─► ship-gate hook
   goal ──► board (intake)    worktree  mega             money_gate
              │                                          advisor (agents/)
              │                            ▲                   ▲
              │                            │                   │
              │                    every phase boundary asks Govern
              │
              │                  OBSERVE                     LEARN
              │                  ───────                     ─────
              │                  stats ◄── ledger            learn ─┬─► propose ──┐
              │                  telemetry ◄── ledger               ├─► drain     │
              │                  session ─┬─► observe                └─► debt      │
              │                           ├─► semantic                            │
              │                           ├─► intel ──► (calls observe)           │
              │                           ├─► audit ──► triage ────────────────┐  │
              │                           └─► recall                           │  │
              │                  bridge ──► board mirror (to Hermes cockpit)   │  │
              │                                                                ▼  ▼
              └──────────────────────────────────────────────────── board (staging/promote)
                                          the loop closes here

   Spanners (one module, two legs), honest and named in ADR-0034:
     board   = Specify (intake)  + Learn (staging/promote)
     session = Observe (capture) + Learn (harvest, via audit triage)

   Off the loop:  cosmetic (statusline)   prose_rag (recall over the corpus; leg assignment
                                          is a documented deviation, see module-registry)
```

---

---

## 4. The classify path: one task in, four routing decisions out

`classify` is the kit's router. It is four independent classifiers, not one: each answers a
different question and each has a different consumer. Nothing here decides anything by itself;
every output feeds a gate, a lens, or a worker slot.

```
                                       ┌────────────────────────────────────────────────┐
  a task description  ─────────────►   │            lib/classify/                       │
  a changed-file set  ─────────────►   │                                                │
                                       └───┬──────────┬──────────┬──────────┬───────────┘
                                           │          │          │          │
                     ┌─────────────────────┘          │          │          └──────────────┐
                     │                                │          │                         │
                     ▼                                ▼          ▼                         ▼
              lane-classify                    role-classify   task-type-classify   significance-classify
              (risk)                           (domain)        (work type)          (understanding debt)
                     │                                │          │                         │
       tiny|normal|full|bug|backfill      security|db-migration| incident|learning|       tap|wave|
                     │                    frontend|performance| planning|operate|eval|    not-significant
                     │                    data-etl|infra|api|   research|doc|migration|            │
                     │                    generic              reconcile|data-tool|                │
                     │                                │          spec-feature                      │
                     ▼                                │              │                             ▼
        ┌────────────────────────┐                    │              │                    quiz-gate ★ tap
        │  gate-ledger required  │       ┌────────────┴───┐          ▼                    (engage/defer/wave)
        │  <lane>                │       │                │   proof-gate contract         + learn debt row
        │  reads the lane x      │       ▼                ▼   (docs/verification/               │
        │  phase matrix straight │  review-team      execute        task-types.md:              ▼
        │  out of WORKFLOW.md    │  domain LENS      WORKER slot     which artifact this    weekend-batch
        │  (one source, no copy) │  (api/frontend/   (agent-for:     work-type owes)        paydown
        └───────────┬────────────┘   infra/perf-     data-etl-worker,
                    │                 reviewer)       db-migration-worker;
                    ▼                                 reviewer domains
        the gates the ship-gate hook                  deliberately return
        will REFUSE to push without                   EMPTY: a read-only lens
                                                      never becomes a worker)
```

**Why the reviewer/worker split matters** (SPEC-111): `role-classify agent-for` returns a name
only for the two WRITE domains. Ask it for `security` and it returns nothing, on purpose: a
security lens is read-only and must never be handed a build slot. The same classifier feeds
both sides; the asymmetry is enforced in `agent_for()`, not in the caller's discipline.

**A fifth verb, `route-suggest`, is advisory-only by design.** It reads the ablation ledger and
names the cheapest model tier that passed at parity, and it ABSTAINS when the data is too thin
(which is its current state: the committed proof run is haiku-only, n=1). No command or hook
calls it, and that is correct: it suggests to a human, it never routes. Reach it with
`classify route-suggest <ledger.tsv> <task>`.

**The lens map itself** (which lens fills which V-model row, and which command dispatches it)
lives in `docs/WORKFLOW.md` "The V-model lens", not here. Two homes for one table is how the
README's dispatch column drifted; C9 of the kit contract now lints every "dispatched by /X"
claim against the command that supposedly does it.

## Reading order

- New to the kit: `README.md` (the five legs) -> `docs/WORKFLOW.md` (how a run moves) -> this
  page (how data moves).
- Adding a signal pipeline: `docs/kit-contract.md` (the rules) -> flow 1 above (where your
  output has to land) -> `docs/specs/SPEC-200-signal-pipelines.md` (why).
- Debugging "where did my evidence go": flow 2.
