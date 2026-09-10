# Proof of done: step 7b scans first and `Built:` names the home it joins

Branch `fix/wrap-candidates-scan`. Behavioral surface: `lib/wrap/report-lint.sh` now rejects a
`**Built:**` line that is only a path and a commit (no `ENHANCE <home>` or `NEW (precedent: ...)`
token) and rejects `SKIPPED:` followed by nothing / none / no candidates. `commands/wrap.md` moves
the candidate scan ahead of step 0 and redefines a candidate to exclude the session's own
deliverable.

## Why

Two weeks of real `/kit:wrap` reports, tallied from the session transcripts: every non-empty
`Built:` line named the session's own deliverable (`google-cred-probe (#2451)` seventeen times,
`suppress-match-check (#215)` five times), thirteen read `SKIPPED: nothing to build`, and none named
an existing tool to enhance. The standalone closeout this step replaced printed `<label> ENHANCE
<home>: <file, insertion point>` most sessions (`wake-probe ENHANCE tools/alert-triage`, `a1 re-seed
ENHANCE rotate-heartbeat-token`, `wl-query fields preset ENHANCE wl-query.sh`), and the following
session built it.

## Runs

| # | Command | Exit | Verdict |
|---|---|---|---|
| 1 | `bash tests/test-wrap.sh` | 0 | PASS (252, five new lint cases) |

## Negative control

```
## Negative control (negctl)
Command: bash tests/test-wrap.sh
Exit: 0 (green before mutation)
Mutation: sed -i '' s/enhance/enhancex/ lib/wrap/report-lint.sh
Changed: lib/wrap/report-lint.sh
Exit: 1 (under mutation, RED expected)
Restore: git checkout HEAD -- lib/wrap/report-lint.sh
Exit: 0 (green after restore)
Verdict: PASS
```

Reproduce:

```bash
bash lib/gate/negctl.sh . "bash tests/test-wrap.sh" "sed -i '' s/enhance/enhancex/ lib/wrap/report-lint.sh"
```

The mutation breaks the token the lint accepts, so the ENHANCE-shaped fixture reads as a bare path
and the case that expects it to pass goes red.

## Not proven here

The scan-before-step-0 ordering is command prose executed by the model. What the lint can hold is
the output shape: a report can no longer claim `Built:` with a bare deliverable or a skip that is
really an empty scan, so the next two weeks of reports will show whether the scan runs.
