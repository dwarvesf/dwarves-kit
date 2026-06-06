# Verification log

> The kit's "Verify before proceeding" principle is only real if the verification
> was **actually run** and the run is **recorded as a re-runnable artifact**. A prose
> "Tests: passing" is a claim, not proof. This directory holds the proof.

## Proof of done

"Done" is not a claim, it is a **proof of done**: a recorded artifact a skeptic can
re-run. A complete proof of done has three parts:

1. **Green, captured.** The implemented check actually run, with the exact command, real
   exit code, and output excerpt logged (not "tests pass" in prose).
2. **A negative control.** The same check shown to go RED when the work is reverted, so
   the green is not trivially green. A check that passes no matter what proves nothing.
3. **Reproducible.** Re-running the logged `Command:` line reproduces the verdict.

For a load-bearing change, all three are required. Green-only is a weak proof; it says
"it passes," not "it would have failed without the work."

## What this is

One file per spec: `docs/verification/<spec-slug>.md` (same slug as the spec and the
matching `docs/implementation-notes/<spec-slug>.md`). Every verification run , whether
it came from `/kit:execute`'s inline pipeline, a `/kit:verify` re-run, or a phase
checkpoint , appends one entry capturing the exact command, its exit code, an output
excerpt, and the verdict. A later reader pastes the `Command:` line and gets the same
verdict: that is the regression check.

This mirrors the `docs/implementation-notes/` log (SPEC-041): a durable, append-only,
git-tracked record produced as a by-product of the normal flow, not a separate chore.

## Entry shape

````markdown
## YYYY-MM-DD HH:MM <VERDICT> -- SPEC-NNN [TASK-NNN | integration | phase-N | manual]
- Command: `<exact, re-runnable command>`
- Exit: <integer exit code>
- Output (excerpt):
  ```
  <the decisive lines: pass/fail counts, the failing assertion, the summary line>
  ```
- Verdict: PASS | FAIL | [NO EXECUTABLE CHECK: <reason>]
- Note: <optional one line, e.g. which AC this covers>
````

Rules:

- **`Command:` must be the real, pasteable command** (`bash tests/test-meta.sh`,
  `go test ./...`, `rg -c 'marker' file && ...`), not a description of one. If someone
  cannot copy it and re-run it, it does not belong on that line.
- **`Exit:` is the captured exit code**, not a retyped guess. `0` is not assumed from
  a clean-looking transcript; it is the actual `$?`.
- **`Output (excerpt):` is real captured stdout/stderr**, trimmed to the decisive
  lines. Never fabricate or paraphrase output.
- **The no-check path is explicit.** When a task genuinely has no runnable check
  (subjective prose, design judgment, a doc with no assertion), write
  `[NO EXECUTABLE CHECK: <reason>]` as the verdict. This is an honest, allowed
  outcome , it is **never** silently upgraded to PASS. A false PASS is a worse
  failure than an honest no-check.

## Who writes it

- `/kit:execute` , the orchestrator appends an entry at each phase checkpoint
  (Step 3) and at completion (Step 4), and surfaces the file path in its summary.
- `/kit:verify` , the read-only on-demand check appends one entry per run. Writing a
  record of the run is not "changing the code under test"; it is the point.
- `task-verifier` (agent) , reports a `Verification record` block (command + exit +
  excerpt) in its verdict; the orchestrator transcribes it into this log. The agent is
  read-only on code and does not write here itself.

## Re-running (the regression check)

To confirm a past verdict still holds, open the spec's verification log, copy the
`Command:` line from the entry you care about, run it, and compare the exit code and
output excerpt. Same verdict = no regression. Different verdict = a regression the log
just caught.

## Negative control (a green check is only proof if it can fail)

A PASS entry alone is weak: it shows the check passes, not that the check *exercises*
anything. A test that would pass no matter what is not proof. So a high-value
verification log also records a **negative control** at least once per change: revert
the implementation, run the same check, confirm it FAILS, then restore and confirm it
passes again. Record the RED run as a `NEGATIVE CONTROL` entry (verdict
`RED-as-expected`, the real failing exit code + excerpt). This is the difference between
"it passes" and "it would have failed without the work." Skip it only for trivially
mechanical changes; for anything load-bearing, the negative control is what makes the
green entry trustworthy.

Source: extends ADR-0005 (verify-then-trust) and SPEC-041 (the implementation-notes
log precedent). This is the *recording* dimension of verify-arm hardening , making the
executed run a recorded, re-runnable artifact. It is distinct from ID-020 (the
removal-class absence check, already covered by `task-verifier` Section 1b); the two
are neighbors in the "verify is more than presence" theme, not the same fix.
