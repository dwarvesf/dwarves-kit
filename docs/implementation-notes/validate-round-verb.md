# Implementation notes: validate-round-verb

Delta from `docs/specs/SPEC-363-validate-round-verb.md`.

Spec written and recorded. Build not started, so no deviation yet.

## Round 1: NEEDS REVISION, folded

7 parallel reviewers; Reviewer 6 `design-bearing=yes pass`. Three criticals, all folded into the spec:

- The approval now binds to ship-gate's spec glob (`open` refuses a stub or foreign-repo spec). DEC-F widened.
- `incomplete` pairs both brackets with a `GATE` line, including `design-record skipped "incomplete: <reason>"`. DEC-H is new. This reverses the round-0 choice to keep step 5's unpaired `design-record end`.
- T3 now covers `commands/execute.md` and `commands/wrap.md` as well as `commands/spec.md`.

Warnings folded: `key=value` arguments for `close`; drift check simplified to "last line equals the `ROUND open` line" (DEC-D rewritten, no line count or prefix hash); awk-only `ROUND` reads; porcelain excludes with a writer table in Grounding; no edits between `open` and `close`; NEEDS-REVISION resets the void budget; `incomplete --stale`; resumable `closing` state (DEC-I); forged-record exit 4; per-rid mkdir lock; DEC-B rewritten; wider C11 and C12; T4 unconditional and last.

## Decided at spec time, flagged for the validators

- Brackets are per round (DEC-B). `caught=true` marks the round that caught; the validation-wide value is derived from `ROUND` lines.
- C10d needs a test-only failure hook (`GL_VR_FAIL_AFTER`) in `append_run_line`'s caller to simulate a mid-write failure. If the build finds a cleaner seam, it records the change here.
