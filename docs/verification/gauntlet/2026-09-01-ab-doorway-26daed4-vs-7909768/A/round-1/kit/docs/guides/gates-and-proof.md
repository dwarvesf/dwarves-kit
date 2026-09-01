# Gates and proof of done (user guide)

Almost everything in the kit ADVISES; exactly four things BLOCK. If a run
stopped hard, you hit one of these, and each has a designed way through that is
never "disable the gate":

```
 the 4 hard stops                           the way through
 ─────────────────                          ───────────────
 spec-drift guard ......... build diverged  amend the spec (add-only) or
   from the spec's contract                 re-scope; then continue
 verification pipeline .... a task failed   fix-agent retries (cap 2), then
   its verifier                             escalate: the task or spec is wrong
 ship gate + push-to-main . no proof of     produce the proof, or log an
   done for a behavioral change             AUDITED override with a reason
 debug iron law ........... fix attempted   record the root cause first;
   without a recorded root cause            guess-fixes are refused
```

## Proof of done, the part everyone meets

A behavioral change cannot ship on "trust me, it works". The gate wants a file
in `docs/verification/` added by your branch containing:

1. **A green run**: the actual command, its exit code, its output, verdict PASS,
   a run table, or a committed screenshot/GIF for visual work.
2. **A negative control**: proof the check can FAIL, revert the change (or stub
   the input) -> RED -> restore -> GREEN. A check that cannot go red proves
   nothing.
3. **Reproducibility**: the commands are pasteable; someone else could rerun.

Produce it AS you finish (`/kit:verify` does this), so the gate is a
confirmation, not a surprise wall at push time.

## What you do

- **Blocked at ship with no proof?** Run `/kit:verify`, or record the run table
  you already have. Two minutes if the work actually works.
- **Docs-only or scratch change?** Log the audited override with the reason
  (`proof-ledger.sh override '<slug>' "<why>"`). Overrides are visible and
  reviewed, that is the design: honest skips beat fake proofs.
- **The negative control feels silly?** It caught real false-green tests in
  this kit's history. Stub-out -> red -> restore takes a minute and is the
  difference between a proof and a screenshot of green text.
- **A verifier keeps failing a task?** Two retries then escalation is the cap
  for a reason: 3+ failures is a design problem. Reread the spec's task, do
  not ask for a third retry.

## Common questions

- **"Who reviews overrides?"** They land on a ledger, surfaced at retro/audit
  time. Overuse is visible by design.
- **"Why can't I push to main?"** Direct main pushes bypass every gate above;
  the kit refuses them structurally. Branch + PR is the only door.
