# Implementation notes: mega-start-wiring (SPEC-101)

Delta from the spec. Reference, do not restate.

## 2026-07-02 fix site is the driver, not the prose command

**Context:** goal-file 01 + SPEC-101 name `commands/mega.md` as the dispatch owner.
**Decision:** implement in `lib/orchestrate.sh cmd_run`; `commands/mega.md` gets a
one-line pointer only.
**Why:** `commands/mega.md` Step 5 explicitly hands off to `lib/orchestrate.sh run
<dir>` (the non-LLM driver). The prose command never emits the START itself; the driver
is the executable, testable dispatch. A START in prose cannot be pinned.
**Alternatives:** emit inside the spawned `claude -p` session (rejected: the session runs
the goal loop, not assign.md, and the rid/branch does not exist until mid-session).
**Impact:** the spec's "commands/mega.md dispatch" is honored as "the driver mega.md
invokes"; noted in SPEC-101 Root cause.

## 2026-07-02 rid derived from the goal file's `**Branch:**`, START before the branch exists

**Context:** rid = branch slug, but the branch is created inside the session, after dispatch.
**Decision:** derive the rid from the goal file's `**Branch:** <type>/<slug>` header at
dispatch and emit START keyed to that slug.
**Why:** `gate-ledger.sh start` writes to a rid-keyed ledger file and does not require the
branch to exist. `runid` is idempotent, so the driver's raw slug and the session's later
`runid`-normalized rid resolve to the same ledger file.
**Alternatives:** derive rid from the SG-NN id (rejected: would not match the session's real
branch rid, orphaning the START and leaving the run `?`).
**Impact:** assumes declared branch == session's actual branch (the POINTER_PROMPT contract).
If a goal file omits `**Branch:**`, the driver WARNs and skips the START (no wrong rid).

## 2026-07-02 chosen == classified for the automated path

**Context:** `start` records `<chosen-lane> <classified-lane> <chosen-type> <classified-type>`.
**Decision:** the driver sets chosen == classified for both axes.
**Why:** the automated dispatch has no human choosing a different lane/type; it takes the
classifier's suggestion verbatim. Recording them equal is honest and never reads as a
misroute (a false misroute would itself pollute the telemetry this wave is cleaning).
