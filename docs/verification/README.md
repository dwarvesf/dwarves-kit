# Verification log (proof of done) -- the canonical convention

> The kit's "Verify before proceeding" principle is only real if the verification was
> **actually run** and the run is **recorded as a re-runnable artifact**. A prose
> "Tests: passing" is a claim, not proof. This directory holds the proof.

This file is the **single canonical convention** for "is it actually done?" across every
task class. Consumer repos (e.g. ops-toolkit) point here rather than restating it.

## The spine: one scientific method, four stages

Verification is the scientific method applied to a change. Every work item moves through
the same four stages, and each stage is already a beat of the kit's existing lifecycle , the
framework names and records them, it does not add a parallel engine:

| Stage | What it is | Kit beat | Artifact |
|---|---|---|---|
| 1. Hypothesis / assumptions | what we believe is true + what would prove it false | `/kit:think`, `/kit:spec` | the spec + `test-design.md` |
| 2. Test design | the tests to run, acceptance criteria, the expected negative control | `/kit:test-plan` | `test-design.md` (written once) |
| 3. Execution | run the real flow; each run is recorded | `/kit:execute`, `/kit:verify` | `runs/<timestamp>.md` (one per run) |
| 4. Report | the recorded verdict of an execution; versioned | the run file itself | `runs/<timestamp>.md` |

The design is written **once** and is stable. Each **execution** produces its **own
immutable, versioned report** , re-running never overwrites a prior run, it adds a new one.
A skeptic re-runs any recorded execution's `Command:` and reaches the same verdict.

For COMPARATIVE claims (faster/smaller/fewer), add the optional evidence pair
(SPEC-080): `Baseline:` and `Treatment:` (same command, data, env), with
`Delta:` and `Threshold:` , a comparative verdict without the pair is INCONCLUSIVE.

## What "done" means: a proof of done has three parts

"Done" is not a claim, it is a **proof of done**: a recorded artifact a skeptic can re-run.

1. **Green, captured.** The check actually run, captured as evidence, not "tests pass" in prose.
   The capture is EITHER a text run-table (the exact `Command:`, real `Exit:` code, and output
   excerpt) OR, for visual/demo work (a UI, a rendered doc, a CLI demo), a committed **screenshot
   or GIF** embedded in the proof (`![...](path.png|gif|...)`). The gate accepts either form , a
   picture of the thing running counts as "it ran". Pick the form that fits the work-type; non-visual
   logic still owes a run-table.
2. **A negative control.** The same check shown to go RED when the work is reverted, so the
   green is not trivially green. A check that passes no matter what proves nothing.
3. **Reproducible.** Re-running the logged `Command:` reproduces the verdict.

For a load-bearing change, all three are required. Green-only is a weak proof.

## Layout: one design + a runs/ directory per work item

```
docs/verification/<slug>/
├── test-design.md          # stage 1+2, written once: hypothesis, assumptions,
│                           #   test design, acceptance criteria, expected negative control
└── runs/
    ├── 2026-06-09-0142.md  # stage 3+4: one execution = one immutable versioned record
    └── 2026-06-09-1530.md  #   (re-run -> a new file, never an overwrite)
```

`<slug>` is the feature branch name minus its `type/` prefix (same slug as the spec and
`docs/implementation-notes/<slug>.md`). The older flat shape `docs/verification/<slug>.md`
(append-entry, one file) is still accepted by the gate.

**One deliberate exception: `docs/verification/rejected-findings.md` (SPEC-144).** Every other
file directly under `docs/verification/` is a proof-of-done record scoped to one work item's
slug. `rejected-findings.md` is not: it is a cross-cutting, ever-growing, consulted-at-runtime
memory (the review surfaces' rejected-findings ledger), with no owning slug and no immutable
"one record per run" shape. It lives here rather than under `docs/decisions/` because the
sub-goal contract that created it names this exact path; treat it as the one named exception
to the per-slug convention above, not a precedent for a second one.

## Two homes: repo-root layout or co-located with the tool (ADR-0026)

A proof has two equally-valid homes. Pick per context:

- **Repo-root** `docs/verification/<slug>/{test-design.md, runs/}` , the default for a feature
  branch with no single tool home.
- **Co-located** `tools/<name>/docs/proof-of-done.md` , first-class for a tool in a `tools/<name>/`
  monorepo, so the proof travels WITH the code it proves. Optional `tools/<name>/docs/runs/<ts>.md`
  (immutable history) and `tools/<name>/docs/test-design.md` sit beside it.

**The filename is load-bearing.** The gate's only co-located match is a file literally named
`proof-of-done.md` (regex `(^|/)proof-of-done\.md$` in `lib/proof-ledger.sh`); a co-located `runs/`
directory is invisible to the gate. So a co-located canonical proof MUST be the `proof-of-done.md`
file itself and MUST carry the literal gate markers (`Command:`, `Exit:`, `NEGATIVE CONTROL`,
`rollback` / `[UNAVAILABLE`) in its body.

**Generators write run ledgers, never the canonical.** A prover script (a `prove.py`-style "run the
real commands and capture the results" helper) writes immutable, accumulating records under
`runs/<ts>.md`; the canonical `proof-of-done.md` is hand-authored and only references the latest
ledger. A generator that targets `proof-of-done.md` itself clobbers the review layer on every run
(found live: a consumer tool's prover overwrote the hand-authored canonical; the fix was a
one-line output-path change). Corollary for multi-feature tools: ONE `proof-of-done.md` per tool,
structured as a feature index, because per-feature names like `proof-of-done-<feature>.md` do not
match the gate regex and are invisible to it.

For the kit's OWN runs (a `rid`'s gate/run ledger, `lib/gate-ledger.sh`), the generator is
`lib/proof-table-gen.sh <rid>` (SPEC-132): it renders the confirmation table from
`logs/runs/<rid>.log` under `docs/runs/<rid>.md`, hard-refuses any out-path whose basename is
`proof-of-done.md`, and surfaces sub-goal 01's `caught=`/timing marker when present, degrading
gracefully when absent. **Honesty note:** today the only call site that emits the OUTCOME
marker (SPEC-129) is `hooks/ship-gate.sh` at the ship boundary, so the generated Caught/Duration
columns reflect the Ship phase only, not a per-phase measurement across the whole run, no
matter how many phases the ledger otherwise records. WORKFLOW.md "## Gate ledger and ship
enforcement" states this scope alongside the marker's own convention.

### Optional table-first review layout

Any proof (either home) MAY use a **table-first** layout optimized for a reviewer scanning top-down,
instead of the run-log shape below. The tables are the human surface; the run-detail section keeps the
literal markers, so the gate is unaffected:

```markdown
# Proof of done: <name>
Profile: tool-build|feature|eval   Proof class: stateful|behavioral|inert

## 1. Acceptance criteria     | # | Criterion | Status | Evidence |   (the AC table, at the top)
## 2. Implementation          | Aspect | Detail |   (What / Where / How it runs / Reversibility)
## 3. Confirmation (runs)      | Run | When (ISO+tz) | Command | Exit | Verdict |
## 4. Run detail               ### R1 GREEN — Command: … Exit: … Verdict: PASS
                               ### R2 NEGATIVE CONTROL — … ; ### R3 ROLLBACK/RESTORE — …
## 5. Reproduce                `<idempotent re-run command>`
```

### Work-type dialects (one spine, the body adapts)

| Work-type | Confirmation shape | extra |
|---|---|---|
| one-shot CLI / data tool | green run + negative control (revert -> RED) | reversibility = git revert / N-A |
| stateful daemon / service | green = liveness; negative control = kill -> down; restore = rollback | topology (what runs where) |
| recurring action / loop / workflow / cron | an append-only run ledger (row + detail per execution) + a liveness/monitoring signal | schedule + monitored signal |
| eval / experiment | a thin pointer to `experiments/<slug>/TEST-REPORT.md` (the single source of measured numbers) | numbers never copied out |

Worked reference: ops-toolkit `tools/{zedra-deploy,growatt-pull,spec-to-cli}/docs/proof-of-done.md`
(SPEC-016). New work uses the directory layout OR the co-located `proof-of-done.md`; both are first-class.

## Three profiles of one spine (not three reinventions)

The three task classes differ only in what `test-design.md` holds and the shape of a run
report. The location and lifecycle are identical , one grammar, three dialects:

| Profile | `test-design.md` holds | a `runs/<ts>.md` holds | owning skill |
|---|---|---|---|
| **eval / experiment** | suites, metrics, the falsifiability check | a TEST-REPORT version (generated numbers) + provenance | `tool-eval-experiment` |
| **tool build / port** | Definition of Done, acceptance criteria, the proof-script command | a recorded live run of the real commands | `ops-tool-shape` Done gate |
| **feature / goal** | the test-plan derived from the spec | a `/kit:verify` run + its negative control | dwarves-kit |

The three profiles are **siblings**, not rivals: the eval/experiment profile (worked example
`ops-toolkit/experiments/codebase-tool-benchmark/`) is the research-paper twin of the
feature profile's proof of done. The experiment's **falsifiability check** and the feature's
**negative control** are the same idea (a check that cannot fail proves nothing). The
experiment's single-source GENERATED numbers and the kit's `COUNTS.md` are the same idea (a
figure is generated once, never hand-typed into N docs where it drifts). Keep the profiles
distinct in JOB
(confirmation vs comparison); do not grow a build system for a one-line change, nor a
benchmark for a verification log.

## Risk classes: where the discipline lands

A task's **proof class** decides what "done" needs. Classify with `lib/proof-gate.sh class
"<task>"`; it suggests, a human can override.

| Proof class | What it is | Proof of done required |
|---|---|---|
| **stateful** | deployment, migration, anything touching data / persistent state | Exercise the REAL flow on a copy or dry-run, record it, AND note rollback / reversibility. Never "done" without a recorded run + a rollback path. |
| **behavioral** | implementation that changes behavior (a feature, a logic fix) | Run the REAL primary flow end-to-end (the path the change adds), record it, AND include a negative control (revert -> RED -> restore). |
| **inert** | docs, comments, cosmetic, pure text | Exempt. Record `[PROOF OF DONE: exempt -- <reason>]`. No run. |

- **Run the real primary flow, not a proxy.** The recorded run must exercise the actual
  path the change adds, not a tangential green test that happens to pass.
- **Stateful needs reversibility.** If a flow cannot be exercised here, record
  `[UNAVAILABLE: <reason>]` rather than faking a run.
- The exempt marker is honest, not a loophole. Marking a behavioral/stateful task exempt is
  a finding, not a pass.

## The verify contract: a bounded quality loop

Stage-3 execution for a load-bearing change runs as a **bounded quality loop** on the kit's
existing reviewer dispatch (`/kit:verify`, `/kit:review-team`) , not a new orchestrator:

- **Produce -> critique -> revise.** A producer makes the artifact; a **distinct** reviewer
  (never self-review) adversarially critiques and lists actionable findings.
- **Bounded.** The loop stops when findings reach zero (`clean`) OR a hard round cap is hit
  (default 3). It never runs unbounded.
- **Falsifiable, machine-readable verdict.** Each round's reviewer ends with a verdict
  marker `[[QL-VERDICT round=N clean=BOOL findings=K]]`. Across rounds the finding count
  must **strictly fall** , a loop where findings do not decrease is a finding, not a pass.
- The final `runs/<ts>.md` records the converged verdict + the round-by-round finding counts.

## Enforcement: the ship/merge gate (advice becomes a wall)

`lib/proof-ledger.sh` (wired into `hooks/ship-gate.sh`, ADR-0025) is a **gate at the
ship/push boundary**: a behavioral or stateful change cannot ship without a matching, fresh
proof of done. It keys off the **branch diff**, not a spec, so it fires the same whether the
work came through `/kit:execute` or a freeform `/goal` loop. Properties:

- **Opt-in per repo.** Engages only where this `docs/verification/README.md` exists.
- **Fresh proof only.** The proof must be one the branch itself added/modified.
- **Set-wise for the directory layout.** A `<slug>/` work item is satisfied when, ACROSS its
  files, there is both a green run AND a negative control , the two may live in different
  `runs/` files. A flat `<slug>.md` or `proof-of-done.md` is still validated per-file.
- **Honest passes.** Inert passes with no ritual; stateful passes with a rollback note or
  `[UNAVAILABLE: reason]`.
- **Logged override, never silent.** `bash lib/proof-ledger.sh override <slug> "<reason>"`
  leaves an audit trace. There is no silent bypass.
- **Fails open on ambiguity** (no repo, empty diff, missing tooling) so a gate bug never
  blocks unrelated work.

## test-design.md shape (written once, stage 1+2)

> **Quality bar for what goes in it:** `docs/verification/test-design-standard.md` , the
> coverage rule (every AC -> a test), the test ladder (smoke -> unit -> integration -> live ->
> adversarial), falsifiability (a negative control per load-bearing claim), the one-source /
> three-roles split, and the pre-done sign-off checklist. The matrix lives in `test-design.md`;
> `runs/` are the records; a report is an index, never a copy.


````markdown
# Test design -- <slug>
Profile: eval | tool-build | feature
Proof class: stateful | behavioral | inert

## Hypothesis / assumptions
- What we believe is true, and what we are proving.
- What would prove it FALSE (the falsifiability hook, stated up front).

## Test design
- The tests / flows that exercise the real change (acceptance criteria, one per line).
- The expected negative control: which revert should turn the check RED.

## How to re-run
- The exact command(s) a skeptic pastes to reproduce any run.
````

## runs/<timestamp>.md shape (one immutable record per execution, stage 3+4)

````markdown
## YYYY-MM-DD HH:MM <VERDICT> -- <slug> [green | negative-control | integration | phase-N]
- Command: `<exact, re-runnable command>`
- Exit: <integer exit code>
- Output (excerpt):
  ```
  <the decisive lines: pass/fail counts, the failing assertion, the QL-VERDICT marker>
  ```
- Verdict: PASS | FAIL | INCONCLUSIVE | RED-as-expected | [NO EXECUTABLE CHECK: <reason>]
- Note: <optional one line, e.g. which AC this covers, or the round-by-round finding counts>
````

Rules:

- **`Command:` is the real, pasteable command**, not a description. If it cannot be copied
  and re-run, it does not belong on that line.
- **`Exit:` is the captured exit code**, the actual `$?`, not a retyped guess.
- **`Output (excerpt):` is real captured stdout/stderr**, trimmed to the decisive lines.
  Never fabricate or paraphrase output.
- **The no-check path is explicit.** Write `[NO EXECUTABLE CHECK: <reason>]` rather than a
  fake PASS. A false PASS is a worse failure than an honest no-check.
- **A run file is never overwritten.** A re-run is a NEW file (new timestamp). History is the
  point.

## Who writes it

- `/kit:execute` , appends a run record at each phase checkpoint and at completion.
- `/kit:verify` , the read-only on-demand check writes one `runs/<ts>.md` per run, drives the
  quality loop, and produces the negative control. Writing the record is the point, not a
  change to the artifact under test.
- `task-verifier` (agent) , reports a `Verification record` block in its verdict; the
  orchestrator transcribes it. The agent is read-only on code.

## Negative control (a green check is only proof if it can fail)

Record a negative control at least once per change: in a throwaway `git worktree` off the
merge-base, revert the implementation, run the same command, confirm it FAILS, then discard
the worktree (the shared checkout is never reverted). Record the RED run as its own
`runs/<ts>.md` with verdict `RED-as-expected` and the real failing exit + excerpt. This is
the difference between "it passes" and "it would have failed without the work."

Source: extends ADR-0005 (verify-then-trust), SPEC-041 (the implementation-notes log),
SPEC-042/044/045 (proof of done + task-type contract + consumer-repo enforcement). This adds
the scientific-method spine, the per-work-item directory layout, and the quality-loop verify
contract on top of that lineage.
