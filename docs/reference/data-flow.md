# Data flow

`docs/reference/architecture.md` says what the pieces are. `docs/WORKFLOW.md` says how one RUN moves
through the phases. This page says how DATA moves: where a signal is born, what it becomes,
and how it closes back into the next run. It is the data-flow view next to the architecture and
workflow views.

Three flows, one per substrate:

1. **The signal path** (Watch -> Reflect -> Shape): telemetry becomes a proposal becomes work.
2. **The ledger path** (Build -> Check -> Watch): a run writes evidence; the gates and the
   lenses read it.
3. **The module map**: who calls whom, grouped by stage.

---

## 1. The signal path: telemetry -> proposal -> board -> ship

The Reflect stage's whole job. Every arrow is code, not intent; the names are the callables.

```
  SOURCES                COLLECT + ANALYZE            PROPOSE              HUMAN         WORK
  ─────────              ─────────────────            ───────              ─────         ────

  run ledger  ─────┬──►  stats <lens>          ──┐
  logs/runs/*.log  │     (DuckDB, in-memory)     │
                   │                             │
                   ├──►  lane-telemetry report ──┤ (advisory only,
                   │     (bash/awk)              │  feeds /kit:retro)
                   │                             │
                   └──►  reflect debt list     ──┤
                                                 │
                                                 ├──►  reflect propose ┐
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

**The four invariants of this flow**, and why each is load-bearing:

| Invariant | In this diagram |
|---|---|
| **I1 one currency** | Every proposer lands in the SAME box: `## [staged]` blocks rendered by `lib/reflect/staging-format.py` (the bash hooks render the same grammar through its `.jq` twin). `reflect propose`, `stats anomalies --propose`, `session audit triage`, `session intel propose`, `wrap stage`, `backlog-stage` and `intake-sweep` all write it. |
| **I2 one env family** | That box's path is `BACKLOG_STAGE_STAGING` for every writer (was three different names). |
| **I3 one durable root** | Everything on the left resolves its paths through `kit_resolve_log_dir` (flow 2). |
| **I4 one verb** | `run` produces, `propose` stages, `promote` is the human gate. |

**Staging writes are opt-in for the automatic proposers.** `hooks/backlog-stage.sh`
(SessionEnd, and SessionStart with `--surface`), `intake-sweep` and `reflect propose` write the buffer only when
`BACKLOG_STAGE_AUTO=1`; otherwise the hook returns and `propose` prints its blocks into the
session report. A buffer nobody drained, fed as a side effect, grew the board 13 to 25 rows a
day. The explicit verbs (`stats anomalies --propose`, `session audit triage`, `session intel
propose`, `wrap stage`) write when you run them.

**One writer per file.** The staging buffer and the board each have exactly one locked write
path, and the lock order is board first, then staging.

```
  STAGING BUFFER  _meta/backlog-staging.md            BOARD  _meta/BACKLOG.md

  proposers (python)  ─┐                              capture ──────────┐
  stage hooks (bash)  ─┼─► staging-format.py ─┐       promote ──────────┤
  wrap stage          ─┘   append_blocks      │       assign freeform ──┼─► backlog.sh add ──┐
                                              ▼       wayfind ──────────┤   (board_add.py)   │
  reflect drain ─────────► staging-format.py  LOCK    web-drift ────────┘                    ▼
  board promote ─────────►   rewrite      (tmpdir)                                    board_lock
        │                                                                     (tmpdir, md5 of the
        └─ takes board_lock, then the staging lock                             board's realpath)
                                                      set / dedupe / dedupe-all ─────────────┘
                                                      sync intake (sync_core.apply_board) ───┘
```

- **Staging.** `staging-format.py` owns the lock (a tmpdir flock keyed by the buffer's realpath, like the board lock) and two functions:
  `append_blocks` (append, header written once) and `rewrite` (read-modify-write, re-read
  inside the hold, atomic replace). The bash hooks reach them through the `append` CLI verb.
  A promote therefore keeps a block appended while it ran, and a block that changed after it
  was listed (expired by drain) is skipped, never minted.
- **Board.** New rows come from `backlog.sh add` (`lib/board/board_add.py`), which mints the id
  from a fresh read inside `board_lock` and writes the row in the target table's own column
  count, read from its header. `capture` and `promote` call it; the prose commands (`/kit:assign`
  freeform, `/kit:wayfind`, `web-drift`) run the verb instead of hand-editing. `set`, `dedupe`
  and `dedupe-all` mutate under the same lock. `sync intake` mints in `sync_core` under that
  lock too. `board writeback` edits `BACKLOG.md` on a held `chore/board-sync` branch, not the
  working copy.

**`board promote` is the only edge from staging to the board; it is not the only edge into
the board.** It is a person's decision, and `reflect drain` is how they review the pile (aging
stale blocks to `[expired]`). Propose-don't-dispose: a machine may fill the staging buffer
forever and never move the board. `capture`, `/kit:assign` freeform, `/kit:wayfind`, `web-drift`
and `sync intake` file a row directly because a person or a declared source asked for that row.

**Two proposers reach staging only when run.** `session intel propose` (the digest's synthesis and
repeat proposals) and `reflect propose --retro` (a retro's action items) are explicit verbs. The
digest and the retro keep their prose; a lead nobody runs the verb for is a lead nobody actions.

**One renderer.** Every writer renders a block through the shared `lib/reflect/staging-format.py`.
It collapses whitespace per field, so an embedded newline in extracted text cannot forge a second
`## [staged]` block. C5 of the kit contract requires the module to be LOADED, not merely named,
and its negative control plants a private renderer. The only second copy of the grammar is the
`.jq` twin, pinned to the Python on goldens by `tests/test-staging-format-jq.sh`. The incident
behind this rule: `docs/retro/RETRO-2026-10-25-data-flow-incidents.md`.

---

## 2. The ledger path: who writes evidence, who reads it

One append-only corpus, one resolver. Every path below is derived, never hardcoded.

```
                        ┌────────────────────────────────────────────┐
   WRITERS              │   kit_resolve_log_dir()                    │      READERS
   (Build + Check)      │   lib/telemetry/kit-log-dir.sh             │      (Watch + Check)
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
   journal (idempotency)│   <root>/queue-journal.tsv                 │ ◄──── reflect debt list
                        └────────────────────────────────────────────┘        (| DEBT | rows)
                                          ▲                                ◄──── mega report /
                                          │                                       mega review
   hooks (ship-gate, safety-gate, ...) ───┘  ── read the SAME ledger to decide
                                              whether a push may proceed (Check)

   NOT in the ledger, by design:
     ~/.claude/intel/{intel,audit}-YYYY-MM-DD.md   the Watch reports (dated artifacts)
     _meta/backlog-staging.md                      the proposal buffer (flow 1)
     <root>/hooks/<hook>.log                       hook diagnostics (under the ledger root, not corpus)
```

Why one resolver matters: a plugin reinstall wipes `~/.claude/dwarves-kit/`. Anything that
defaults there loses its history. The queue journal IS the queue's idempotency state, so a wipe
re-runs completed work. That is why SPEC-097 exists and why C6 of the kit contract lints for it.
The hook logs follow the same root (`lib/telemetry/hook-log-dir.sh`). History:
`docs/retro/RETRO-2026-10-25-data-flow-incidents.md`.

---

## 3. The module map, by stage

Who calls whom is drawn in `docs/SYSTEM-DESIGN.md` "How the clusters connect", the one owner of
the module map. This page keeps only the stage assignment it adds.

```
   Spanners (one module, two stages), honest and named in ADR-0034:
     board   = Shape (intake)  + Reflect (staging/promote)
     session = Watch (capture) + Reflect (harvest, via audit triage)

   Off the loop:  cosmetic (statusline)   prose_rag (recall over the corpus; stage assignment
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
        │  <lane>                │       │                │   proof-gate contract         + reflect debt row
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

**Why the reviewer/worker split matters**: `role-classify agent-for` returns a name
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

- New to the kit: `docs/reference/lifecycle.md` (the five stages) -> `docs/WORKFLOW.md` (how a run moves) -> this
  page (how data moves).
- Adding a signal pipeline: `docs/reference/kit-contract.md` (the rules) -> flow 1 above (where your
  output has to land) -> `docs/specs/SPEC-200-signal-pipelines.md` (why).
- Debugging "where did my evidence go": flow 2.
