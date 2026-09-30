---
description: "Whole-spec execution with verification. Dispatches one builder for the whole spec, verifies every task's criteria once at the end, retries fixable failures (max 2), names what did not ship."
---

Self-intro (AGENTS.md "Self-intro" convention): open your first reply with exactly one banner line, `[kit:execute] Execute the approved spec: one builder for the whole spec, verify every task at the end.`, then proceed.

You are an execution orchestrator. Take an approved spec, hand it to one builder subagent as a brief, verify the result once at the end, and handle failures.

## Prerequisites

Before starting, verify:
1. `docs/specs/SPEC-NNN-<slug>.md` (or `ROADMAP.md`) exists and has status `APPROVED` or `VALIDATED`
2. The spec has acceptance criteria, a `## Verification` section, and a `## Task Breakdown`
3. Git is on a feature branch (not main/master)

If any prerequisite fails, tell the user what's missing and stop.

### Spec->build lane re-check

The lane is frozen at `/kit:assign` classify time -- every re-classify trigger up to
this point keys on the ORIGINAL task text (intake, `/kit:grill` answers, the
spec-drift re-check), never on scope that only became concrete once the spec was
written. This is the spec->build boundary: the spec is VALIDATED/APPROVED and build
is about to start, so it is the first point a `tiny`/`normal` task's emergent
auth/data-model/migration scope is visible. Re-classify, up-only, before dispatching
Step 1:

```bash
RID=$(bash lib/gate/gate-ledger.sh rid)
# CURRENT_LANE = the lane already recorded for this run (the spec's `Lane:` header,
# or the last `gate-ledger.sh start`/`start --amend` line for $RID if the header is
# missing).
SUGGEST_FILE=$(mktemp)   # escalate prints one `LANE-SUGGEST: full (...)` line on stderr; keep it
bash lib/classify/lane-classify.sh escalate "$CURRENT_LANE" docs/specs/SPEC-NNN-<slug>.md 2>"$SUGGEST_FILE"
```

Spec words never pick `full`: a hard-gate match is only a `LANE-SUGGEST` line, and the operator assigns `full`. Show that line at the Step 1 go checkpoint so the operator can assign it before the build. `ESCALATE` below is for the lighter lanes.

- **`ESCALATE <current> -> <heavier>`**: the spec's own text classifies to a heavier lane
  than the one it carries. Re-plan up-only -- this never stops the run, it only adds
  rigor:
  1. `bash lib/gate/gate-ledger.sh start --amend "$RID" <heavier> <classified-lane> <chosen-type> <ctype> <repo>` -- readers take the LAST START-AMEND, so the ledger's effective lane becomes `<heavier>` and `required <heavier>`'s extra measure-twice gates are now required for this run.
  2. Bump the spec's `Lane:` header UP to `<heavier>` (never down) -- `hooks/ship-gate.sh` reads that header to pick the required gate set, so the heavier set is enforced at ship, not just recorded mid-flight.
  3. `bash lib/gate/gate-ledger.sh action "$RID" "lane escalated <current> -> <heavier> at spec->build boundary"` -- one durable line naming the escalation.
- **`HOLD <current>`**: the spec-implied lane is the same or lighter than the current
  one. Do nothing. This is the downgrade guard (mirrors `lane-classify.sh check`):
  escalation only ever adds rigor, it never removes it, and a lighter re-classification
  is refused.

Advisory + recorded, not a hard block (per PHILOSOPHY): `escalate` always exits
0, and a missed or skipped re-check does not stop `/kit:execute`. An unescalated
under-sized lane still surfaces later, the same place every other lane gap does
(`hooks/ship-gate.sh` at push, `lib/telemetry/lane-telemetry.sh misfires` at `/kit:retro`).

### Validation preflight

Runs after the lane re-check above, so an escalation to `full` picks the Opus tier, and before the build. This covers hand-written specs and specs from any path that skipped `/kit:spec`. Take the effective lane: the same `CURRENT_LANE` the re-check resolved (the spec's `Lane:` header, else the last START or START-AMEND line), after any escalation. On `normal`, `full`, or `backfill`, look for a passing validation under `$RID`, the LAST `validate` GATE line, so a newer failed validation is never masked by an older pass:

```bash
bash lib/gate/gate-ledger.sh show "$RID" | grep -Ei '\| GATE \| validate \| ' | tail -1 | grep -Eq '\| (ran|override) \|'
```

A match means the spec passed validation; go on. No match (no line, or the last validate line is a `skipped` from a failed validation) means execute dispatches the validator `/kit:spec` step 5 defines (each dispatch description carries `rid=<rid>`): the same fresh-context, read-only `general-purpose` subagent and prompt, Sonnet on normal and backfill, Opus on full, with `bash lib/gate/gate-ledger.sh outcome <rid> Validate start` and `bash lib/gate/gate-ledger.sh outcome <rid> design-record start` written before the dispatch. The dispatch is `/kit:spec` step 5's parallel round: one `Reviewer N only` subagent per `### Reviewer N:` heading, Reviewer 6 always on Opus, the lead merging by rule, and the single-pass validator only as the fallback. A second re-validation needs `operator_directed_build: true` in this run's own brief. An incomplete round stops before the build, records per `/kit:spec` step 5, and asks the operator. On the report:

- **APPROVED:** the lead records per `/kit:spec` step 5, folds the warnings (warnings only) into the spec, flips Status to `VALIDATED`, and proceeds to the build.
- **Any critical, including a Reviewer 6 BLOCK:** execute stops before the build with nothing folded and asks the operator, because folding a critical is a scope call the loop must not make alone. On that stop it still records `bash lib/gate/gate-ledger.sh record <rid> Validate skipped "NEEDS REVISION: <criticals>"`. On a Reviewer 6 critical, record `bash lib/gate/gate-ledger.sh record <rid> design-record skipped "critical: <finding>"`; otherwise Reviewer 6 passed, so record `bash lib/gate/gate-ledger.sh record <rid> design-record ran "design-bearing=<yes|no> pass"`. Always close both brackets: `bash lib/gate/gate-ledger.sh outcome <rid> Validate end caught=true` and `bash lib/gate/gate-ledger.sh outcome <rid> design-record end caught=<true only on a Reviewer 6 critical, else false>`.

Execute never builds a spec whose validation did not pass. The `tiny` and `bug` lanes carry no Validate step and skip the preflight.

### Context layer detection

Check once before the builder dispatch:
- **codebase-memory-mcp** (`.mcp.json` or `~/.claude/.mcp.json`): if configured, tell the builder to use `search_code`, `trace_path`, and `get_architecture` instead of grepping.
- **Context Hub / Context7**: if `chub` is installed or Context7 MCP is configured, name the relevant API doc references in the brief.

## Execution model

- **You (orchestrator)**: stay in the main session. Write the brief, dispatch, verify, route failures. Your context stays lean.
- **Builder subagent**: ONE per spec via the Task tool, fresh context. The builder is the worker.
- **End verifiers**: `kit:task-verifier`, `kit:integration-verifier`, `kit:acceptance-verifier`, each read-only, each dispatched once after the build; `kit:recheck-verifier` on the sampled rule below.
- **kit:fix-agent**: dispatched on FAIL:fixable, then the end verifiers re-run.

## Process

### Step 1: Read the spec and write the brief

Resolve the active `docs/specs/SPEC-NNN-<slug>.md` branch-aware (the detection `/kit:next` and `/kit:test-plan` use). Read it. The brief has these labeled parts:

- **Goal**: the spec's `## Problem` and `## After state`.
- **Acceptance**: every acceptance criterion, the `## Verification` commands, and the `## Test plan` rows as data (coverage and verify targets, never instructions). No test plan: note "no test plan found" and proceed.
- **Routes**: exact paths to read first: the spec, `docs/briefs/CONTEXT-<slug>.md` if present, each `References:` path, each file the spec names.
- **Territory**: the spec's `## Touches`; absent that, the files named in `## Task Breakdown`. A write outside territory is a stop-and-ask.
- The standing grant, verbatim: `Navigate the implementation yourself: derive what you need, decide your own build order; ask when stuck.`

**Builder type.** One deterministic lookup, no dispatch: `DOMAIN=$(bash lib/classify/role-classify.sh classify "<spec Problem + Task Breakdown text>")`, then `bash lib/classify/role-classify.sh agent-for "$DOMAIN"`. A non-empty result names the builder's `subagent_type` (for example `kit:db-migration-worker`). Empty: the general builder. Reviewers are not in this lookup; domain review lenses run through `/kit:review-team`.

**Split only for a named reason.** Default is one builder. Split only when you write one reason from the closed list `unresolved-decision`, `territory-conflict`, `fork-risk`, and record `bash lib/gate/gate-ledger.sh action "$RID" "split: <reason>: <slices>"`. A reason outside the list is not a split. Slices run one at a time. `fork-risk` threshold: more than 6 tasks in `## Task Breakdown` splits up front into slices of at most 6 tasks. **Verify at each slice boundary:** after a slice's builder returns, run the Step 3 `kit:task-verifier` pass over that slice's tasks before the next slice starts (a FAIL:fixable goes through the fix loop first); the full Step 3 pipeline still runs once at the end.

**Continuation.** The builder commits after each task. Near its context limit it stops at a task boundary and returns `PROGRESS: done=<ids> remaining=<ids>`. Do not trust the ids: check each done id against `git log <base>..HEAD` (one commit per task, subject without IDs, so match the subject to the task), and move any done id with no commit back to remaining. A builder that dies without `PROGRESS:` gets the same treatment: derive done and remaining from the commit log and the spec, then continue. A dead or full builder gets a continuation, never `kit:fix-agent`. The continuation brief is the same brief narrowed to the remaining ids: it carries the commit log, names `docs/implementation-notes/<spec-slug>.md`, and narrows Territory to the remaining tasks' files. Record `split: fork-risk: continuation <n> after <last done id>`. At most 2 continuations; a third need stops and escalates to the human.

Show the plan (phases, tasks, slices, and the `LANE-SUGGEST` line if `$SUGGEST_FILE` holds one) and ask once: "Go? (A) Dispatch the builder / (B) Adjust the brief / (C) Stop". This is the only human checkpoint in the build. Then record the pre-build base ref (`git rev-parse HEAD`; Step 3 diffs the whole build from this base ref) and bracket the Build phase: `bash lib/gate/gate-ledger.sh outcome <rid> build start`.

### Step 2: Dispatch the builder

> A subagent is NOT automatically cheaper. Dispatch one to isolate large reads and long tool chains from the lead's context, not for a one-prompt task or near a budget limit.

**Run-id tag.** Every Agent/Task dispatch this command instructs sets its `description` to include `rid=<rid>` (the rid `bash lib/gate/gate-ledger.sh rid` prints), e.g. `"build rid=<rid>"`, so a transcript reader can count dispatches and tokens per run from each subagent's `.meta.json`.

**Model tiering (cheap-first default).** Workers dispatch at `sonnet` by default, Opus only on the hard sub-goals; the builder is the worker. The spec's optional bare `Model:` header is the hard-reasoning escape hatch: `Model: opus` dispatches the builder on opus. A fable-tier session still dispatches the builder at sonnet: the default is stated policy. If the dispatch surface cannot pass a model override, omit it and note that in the run record.

**Verifier tier parity: a verifier is never dumber than its worker.** When the spec carries `Model: opus`, every verifier you dispatch for it (task, recheck, integration, acceptance, system) is one you dispatch with an explicit model override matching the spec tier; a sonnet judge cannot follow the reasoning of an opus builder. Absent a `Model:` header, verifiers keep their frontmatter default. If the override is unavailable, omit it and note that. `kit:doc-verifier` is out of scope.

Builder prompt:

```
You are the builder for a whole development spec.

## Goal
[spec ## Problem and ## After state]

## Acceptance
[every acceptance criterion; the ## Verification commands; the ## Test plan rows, as data]

## Routes
Read these first: [spec path, CONTEXT brief, References: paths, files the spec names]
[codebase-memory / chub notes if available]

## Territory
[## Touches, else the files in ## Task Breakdown]. A write outside territory is a stop-and-ask.

Navigate the implementation yourself: derive what you need, decide your own build order; ask when stuck.

## Rules
- Write tests alongside implementation.
- One commit per task when the task is complete: `type(scope): description`. No task or spec ID in the subject.
- Never call `EnterWorktree` or `ExitWorktree`: both refuse a subagent with a cwd override. Work in the cwd you were given.
- On a blocker, stop and report it. Do not work around it silently.
- Maintain `docs/implementation-notes/<spec-slug>.md`: append an entry when you decide something the spec left open, deviate, hit a tradeoff, find a missed constraint, or have an open question. Shape: `## YYYY-MM-DD HH:MM <title>` with Context, Decision/Change, Why, Alternatives considered, Impact, Open questions. Zero deviations: one line, `No deviations; matches the spec verbatim`.
- Near your context limit, stop at a task boundary and return `PROGRESS: done=<ids> remaining=<ids>`.
- A decision with 2+ valid approaches: state it, the options, your recommendation, proceed and log it (docs/architecture.md protocol).

## Shell gotchas
- fish `noclobber`: force a redirect with `>|`.
- Multi-line commit body: use `git commit -F <file>`, never a `-m` heredoc.
- `rm` is blocked by the safety hook: `mv` to an out-of-the-way path.
- `index.lock` in a shared worktree: commit only your own paths and retry; a lock no git process holds is stale, `mv` it aside.

## Decision mode
[lead: pause for human approval / autonomous: proceed with recommendation and log]

## When done (distilled return contract)
A BOUNDED summary, not a dump:
- **verdict**: per task, done or not, with the commit hash.
- **acceptance**: for each acceptance criterion, `confirmed-by: run <command>` or `confirmed-by: read <file:line>`.
- **key findings**: decisions made and any blocker.
- **artifacts**: files changed, tests written, the path and entry count appended to `docs/implementation-notes/<spec-slug>.md` (or `no deviations logged`).
- **read-next**: `file:line` pointers.
```

### Step 3: End verification (THE VERIFICATION PIPELINE)

After the builder (and any continuation) returns, run in order. A verifier judging a commit while someone still edits the tree runs its negative control with `lib/gate/negctl.sh --at <sha> [--path <subdir>] [--setup "<install-cmd>"] <root> "<test-cmd>" "<mutate-cmd>"`, which never writes the live worktree.

1. **Full suite.** Run it, capturing the exact command, exit code, and an output excerpt. Append a verification-log entry to `docs/verification/<spec-slug>.md` (create it if missing; shape per `docs/verification/README.md`: `Command:` / `Exit:` / `Output (excerpt):` / `Verdict:`). No runnable check: record `[NO EXECUTABLE CHECK: <reason>]`, never a fake pass.
2. **One `kit:task-verifier` pass** (rid=<rid>; pass `model: opus` only when the spec carries `Model: opus`, per the parity rule). Input: every task with its acceptance criteria, the whole-build diff from the base ref, and the builder's report. It returns one verdict per task plus the overall verdict. Run the recheck decision (below) at this first end-verifier dispatch.
3. **`kit:integration-verifier`** (rid=<rid>) when `## Task Breakdown` lists more than one task, passing the base ref so it diffs the whole build: every new component reaches its activation point and the spec's end-to-end chains hold.
4. **`kit:acceptance-verifier`** (rid=<rid>) on every build. Its Bash allowlist covers only `npm test`, `go test`, `pytest`, `bash tests/*`, `git diff`; anything else it records as `[NO EXECUTABLE CHECK]`. Run each such `## Verification` command yourself and log `Command:` / `Exit:` / `Output (excerpt):` with the literal tag `(lead-run)` on its Verdict line. A `(lead-run)` row is unaudited evidence: `kit:recheck-verifier` has the same narrow allowlist, so it cannot be rechecked. Do not widen any verifier allowlist.
5. **Check-edit signal.** `bash lib/gate/check-edit.sh <base> <files the ## Verification commands and acceptance criteria name>`. It prints `check-edited: <paths>` when a named file changed or a test file that already existed at the base ref was modified, and `check-weakened: <file>: <line>` for an added skip, xfail, `.only`, `|| true`, or commented-out assert in a test or named file. Any output is surfaced in the summary: a finding, not a block.

**Routing.** PASS continues. FAIL:escalate stops and goes to the human; do not retry it. Read the reason for the policy (`docs/patterns/failure-policy.md`): a reason naming an architecture, risk, or design decision is **escalate**; a reason naming the spec itself as wrong or not worth building is **close**. FAIL:fixable enters the retry loop:

```
retry_count = 0; MAX_RETRIES = 2
while verdict == "FAIL:fixable" AND retry_count < MAX_RETRIES:
    dispatch kit:fix-agent (rid=<rid>) with the verifier's issue list (file paths, fix
    instructions), the acceptance criteria, and the files to modify
    re-run the failing end verifier(s); retry_count += 1
if verdict still != "PASS": apply the PARTIAL rule below
```

**Check the attempt state before you re-dispatch anything.** The loop handles a builder that REPORTED a fixable failure. A builder that went SILENT reported nothing, and a re-dispatch races the original on the same files. First: `bash lib/goal/attempt-state.sh status <spec-slug>`. An attempt in `disconnected` with grace remaining means **resume it with `SendMessage`** and spend no retry. Only once `lose-attempt` succeeds may a fresh builder take the work, as a new attempt and not a fix cycle. Max 2 retries: if it takes 3+, the issue is a design problem, not a code bug. A `kit:fix-agent` that reports it cannot fix an issue: escalate at once.

**Sampled recheck (`kit:recheck-verifier`).** Right-arm PASSes are unreviewed by default, so a fresh-context re-audit samples them. Decide once, at the first end-verifier dispatch, with the script (it resolves `kit_config_get_root execute.recheck_sample 5`, root-only):

```bash
bash lib/gate/recheck-sample.sh decide "$RID"      # normal lane: prints sampled|skipped
bash lib/gate/recheck-sample.sh decide "$RID" 1    # Lane: full (effective lane after the re-check): always sampled
```

- The key is the rid, which exists before the builder dispatches, so no builder commit moves it. The script records `recheck: sampled key=<rid>` or `recheck: skipped key=<rid>` in the ledger, so anyone can recompute the decision. `recheck_sample = 0` never samples; `1` rechecks every PASS. On the full lane every end-verifier PASS is rechecked whatever the config says.
- A sampled run dispatches `kit:recheck-verifier` (rid=<rid>; it pins opus) in a FRESH context on every end-verifier PASS, passing the full verdict block. It RE-EXECUTES the recorded `Command:` and re-judges; it never reads back the recorded `Exit:` text.
- A criterion the builder reported as `confirmed-by: read <file:line>` that no end verifier executed gets a verification-log row whose Verdict carries the literal tag `(self-attested)`. Every `(self-attested)` row is rechecked on every run, sampled or not: the recheck re-reads the cited `file:line` and runs the nearest executable check for that criterion (a `## Verification` or `## Test plan` command that names it). With no such command, the row is logged `unverifiable`.
- A PASS not rechecked gets `Re-audit: SKIPPED (sampled out, 1 in N)`. A recheck PASS is recorded `Re-audit: PASS`.
- A recheck FAIL is recorded `Re-audit: FAIL -- <finding>` and surfaced in the summary. It is ADVISORY + RECORDED, never a mid-flight hard block: it does not reopen the retry loop.

**PARTIAL rule.** When the build cannot meet a criterion after the fix loop, revise the claim down, mark the run `Result: PARTIAL`, name each unmet criterion and where the build stops with `file:line`, and route the gap as a follow-on in the final report. Building the missing capability inside this spec is scope creep. The acceptance verdict stays FAIL and names the criterion; PARTIAL never reads as PASS. The build record says `result=PARTIAL` and the outcome closes `caught=true policy=escalate`.

**Negative control (load-bearing builds: `normal` and `full` lanes).** A green run does not prove the check exercises the build. In a throwaway worktree (`git worktree add` off the build's base ref, never the shared checkout), revert this build's change, re-run the SAME logged command, and confirm it goes RED; then discard the worktree. Append a `NEGATIVE CONTROL` entry (verdict `RED-as-expected`, the real failing exit and excerpt) to `docs/verification/<spec-slug>.md`. If the revert cannot produce a RED, the acceptance check is too weak: fix it before declaring done.

**Gate by proof class (`lib/gate/proof-gate.sh class "<task>"`).**
- **stateful** (deploy / migration / data / persistent state): the recorded run exercises the REAL flow on a copy or dry-run, and the entry carries a `## Rollback` section (`hooks/ship-gate.sh` greps the literal `Command:`/`Exit:` lines plus `rollback`). If the flow cannot be exercised, record `[UNAVAILABLE: <reason>]`, never fake it.
- **behavioral**: run the REAL primary flow the change adds, record it, and produce the negative control above.
- **inert** (docs / comments / cosmetic): exempt. Record `[PROOF OF DONE: exempt -- <reason>]`; skip the negative control. Marking a behavioral or stateful task inert is a finding, not a pass.

After an end PASS, check off every task: `bash lib/spec/spec.sh task-done docs/specs/SPEC-NNN-<slug>.md TASK-A --commit <sha> --verify-log docs/verification/<spec-slug>.md --command '<cmd>' --exit <n> --excerpt '<output>' --verdict PASS` (never commits; commit both paths yourself). The `(verified)` tag separates pipeline-verified tasks from manually approved ones.

### Step 4: Completion

Show the execution summary:

```
## Execution complete
Tasks: [N]/[N] done ([N] verified, [N] manually approved)
Result: [PASS | PARTIAL: unmet criteria with file:line]
Retries: [N] total
Escalations: [N] (required human intervention)
Closed: [N] (spec judged wrong-shaped, dropped rather than retried)
Commits: [N]
Tests: [pass/fail]
check-edited: [paths, or none]
Re-audit: [sampled / skipped key=<sha>; any Re-audit: FAIL]
Files changed: [list]
Implementation notes: docs/implementation-notes/<spec-slug>.md ([N] entries, or "no deviations")
Verification log: docs/verification/<spec-slug>.md ([N] runs recorded; re-run any Command: line to regression-check)

Recommended next steps:
1. /kit:review -- full code review (security + architecture)
2. /kit:docs -- update documentation
3. /kit:ship -- commit and PR (include the implementation-notes path in the PR body)
```

<!-- review-loop --> On the FULL lane, step 1 is not a suggestion: run `/kit:review-team` by default before docs and ship, and drive its Step 5b bounded loop (re-review each fix batch, up to two rounds, per `docs/patterns/review-fix-loop.md`). The verdict stays advisory; the loop runs without an operator prompt. Normal and tiny lanes keep review opt-in.

Record the build gate: `bash lib/gate/gate-ledger.sh record <rid> build ran "tasks=<N>/<N> verified=<N> tests=<pass|fail>"` (add `result=PARTIAL` when the PARTIAL rule applied). This is Build's own phase-owner record, the convention every phase owner uses.

Close the timing bracket opened in Step 1, naming the failure policy (`docs/patterns/failure-policy.md`): `policy=close` if any task was closed as wrong-shaped, else `policy=escalate` if any escalation occurred or the run is PARTIAL, else `policy=continue`.

`bash lib/gate/gate-ledger.sh outcome <rid> build end caught=<true if any escalation/close occurred, the run is PARTIAL, or tests=fail, else false> policy=<close|escalate|continue>`.

## Error handling

- **Builder fails to complete**: run the end verifiers on whatever exists; they decide whether it is salvageable (FAIL:fixable) or needs a human (FAIL:escalate).
- **Spec ambiguity**: a genuine contradiction (the spec disagrees with itself) means stop and ask; do not guess and do not dispatch kit:fix-agent for spec problems. Scope that must be ADDED now ("also do Y") is the declared mid-flight amend path: confirm it with the user first, then amend at a checkpoint (append `- [ ]` tasks, record an `## Amendments` entry) and resume with `/kit:next` (WORKFLOW.md "## Mid-flight amend").
- **Task too large**: within the declared scope, the builder splits it itself. Beyond the spec, confirm the added scope with the user and take the amend path.

## Anti-patterns to avoid

- Do NOT build in the main session. Always dispatch the builder through the Task tool.
- Do NOT skip end verification, even if the builder says "all criteria met."
- Do NOT auto-fix failing tests without the verification pipeline.
- Do NOT silently mutate the spec mid-build. Take the declared amend path: pause at a task checkpoint, append new `- [ ]` tasks, record an `## Amendments` entry, resume with `/kit:next`. A silent rewrite of done (`- [x]`) tasks is forbidden.
- Do NOT retry FAIL:escalate verdicts. They need human judgment by definition.
- Do NOT dispatch kit:fix-agent for more than 2 issues at once. If the verifiers found 5+, the work needs re-implementation, not patching. Escalate.
