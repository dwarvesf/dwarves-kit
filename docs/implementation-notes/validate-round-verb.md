# Implementation notes: validate-round-verb

Delta from `docs/specs/SPEC-363-validate-round-verb.md`.

Spec written and recorded. Build not started, so no deviation yet.

## Round 1: NEEDS REVISION, folded

7 parallel reviewers; Reviewer 6 `design-bearing=yes pass`. Three criticals, all folded into the spec:

- The approval now binds to ship-gate's spec glob (`open` refuses a stub or foreign-repo spec). DEC-F widened.
- `incomplete` pairs both brackets with a `GATE` line, including `design-record skipped "incomplete: <reason>"`. DEC-H is new. This reverses the round-0 choice to keep step 5's unpaired `design-record end`.
- T3 now covers `commands/execute.md` and `commands/wrap.md` as well as `commands/spec.md`.

Warnings folded: `key=value` arguments for `close`; drift check simplified to "last line equals the `ROUND open` line" (DEC-D rewritten, no line count or prefix hash); awk-only `ROUND` reads; porcelain excludes with a writer table in Grounding; no edits between `open` and `close`; NEEDS-REVISION resets the void budget; `incomplete --stale`; resumable `closing` state (DEC-I); forged-record exit 4; per-rid mkdir lock; DEC-B rewritten; wider C11 and C12; T4 unconditional and last.

## Round 2: NEEDS REVISION, folded (operator-directed final round)

7 parallel reviewers; Reviewer 6 pass. One critical, folded: C12 could not pass as written, because five readers take a rid's last timestamp and see a trailing `ROUND` line. AC3, C12, the Invariants and Grounding item 5 now split marker-keyed readers (byte-identical) from last-timestamp readers (identical except the last timestamp). The C12 fixture starts with a `START` line, and `check full <rid>` has its rid.

Lead simplification, applied (DEC-J): the per-rid lock, the forged-record exit 4 and the `GL_VR_FAIL_AFTER` hook are gone. A forged line is a `why=ledger` void listed on stderr; C10d hand-writes the partial ledger. The `closing` line now pins every argument, and resume takes only `<rid> <token>` (DEC-I).

Warnings folded: `head=` and `--untracked-files=all` in the snapshot (DEC-K); glob cache excludes; the negative control moved to "spec dirty at open, edited again"; canonical paths, the raw-slug glob and a symlink refusal in the binding; the full writer table with a corrected cache rationale; `--stale` is a stop outside `/kit:spec`; reviewer scratch in `$TMPDIR`; C13 runs `tests/test-wrap.sh` instead of test-meta; T1 and T2 split; `docs/verification/**` in Touches; a `Chosen:` line in Design.

## Decided at spec time, flagged for the validators

- Brackets are per round (DEC-B). `caught=true` marks the round that caught; the validation-wide value is derived from `ROUND` lines.
