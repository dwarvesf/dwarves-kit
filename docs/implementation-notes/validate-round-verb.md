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

## Round 3: NEEDS REVISION, folded

Folded in the spec only (commit `b92b6513`); no notes entry was written at the time. Summary from that commit: pin and re-hash under `git -C <toplevel>`, a token nonce, pipe and newline refusal, the APPROVED caught rollup, git failures exit 1, the race-window and consumer-writer rows, and the C1b, C1c, C9b and C11 rows.

## Round 4: APPROVED, warnings folded, Status VALIDATED

7 parallel reviewers, 0 criticals. Every consolidated warning was folded; none skipped. New decisions: DEC-U, DEC-V, DEC-W. Widened: DEC-A, DEC-B, DEC-L, DEC-N, DEC-P, DEC-Q, DEC-T. Each new shell mechanism was reproduced in a scratch repo under `$TMPDIR` (git 2.55.0, macOS bash).

Lead calls:

- Git env: unset `GIT_DIR`, `GIT_WORK_TREE`, `GIT_INDEX_FILE` and `GIT_OBJECT_DIRECTORY` at verb start, rather than narrowing DEC-L. Repro: with `GIT_DIR` exported to another repo, `git -C <spec repo> rev-parse --abbrev-ref HEAD` read the other repo (exit 128 on its empty history); after the unset it read `feat/vr-x`.
- Unplanned failures: `set -E; trap 'exit 1' ERR` at verb start, planned refusals as explicit `exit N`. Repro: an unguarded `exit 2` inside a helper gave 1, a missing binary gave 1, a planned `exit 2` stayed 2, and a guarded `ls ... 2>/dev/null | head -1 || true` with no match survived `set -euo pipefail` (unguarded, it killed the shell).
- Token: bash `[[ =~ ]]` refused a valid token followed by `\nextra`; `grep -Eq` accepted it. A `git init --object-format=sha256` repo pins a 64-hex blob, so the grammar takes both lengths.
- Relative spec path: `git -C <toplevel> hash-object ../docs/specs/X.md` from a subdirectory failed with 128; the `pwd -P` canonical path hashed fine. So the pin and every hash use the canonical absolute path.
- Spec removal at `close`: `-f`, `! -L`, `-r` sorted a regular file, a symlink, a missing file and a mode-000 file correctly. `top=` is stored on `ROUND open` so `close` never re-derives the toplevel from a possibly missing directory (DEC-V).
- `<toplevel>` is a prefix of the canonical spec path: `git rev-parse --show-toplevel` returned the physical `/private/var/...` path, matching `pwd -P`.
- DEC-N window, tightened beyond the warning: the warning bounded the window by the latest `GATE | validate | ran` line, but a fallback validation writes `OUTCOME validate end caught=true` after its `ran` line, inside that window. The window now counts only `end` lines inside verb round blocks (after `ROUND closing`, before the next `ROUND` line), and it reads only lines before this round's own `closing`, else the APPROVED round's own `ran` line would empty it. A scratch awk over four fixture ledgers gave the expected values: NEEDS-REVISION then APPROVED (validate true, design-record false); legacy `caught=true` before the first open (false); a fallback `ran` plus `end caught=true` (false on both gates); R6 critical, then R6 pass, then APPROVED (design-record true).
- `hooks/ship-gate.sh` gets trailing comments only, so the line numbers 64 and 224 the spec cites stay valid.
- T3 exit rule: 64 allows one corrected re-run of the same sub-verb; only `close` returns 2.

## Round 4 post-fold check: five lead decisions applied

Status stays VALIDATED. Spec-only edits:

- DEC-X is new: `hooks/ship-gate.sh` is not edited. The T1a comment edits and the `## Touches` entry are gone; the cross-reference lives only in `lib/gate/gate-ledger.sh`, and the C11 ship-gate agreement case guards drift. Reason: any byte change to `ship-gate.sh` breaks the sha256 trust pin in `hooks/codex-hooks.json`. `bash lib/codex/repin.sh check` reports a stale pin, and Codex ship-gate calls exit 2. This supersedes the round 4 note that ship-gate gets trailing comments.
- The four-variable unset is now `unset $(git rev-parse --local-env-vars)`, git's own list (adds `GIT_COMMON_DIR` and `GIT_ALTERNATE_OBJECT_DIRECTORIES`). C1b gains a leg with `GIT_COMMON_DIR` exported to another repo. DEC-L updated.
- ERR-trap contract stated precisely: set inside `validate_round()` only; planned exits (1, 2, 3, 64) issued in the verb's main shell, never inside `$(...)` or a tested helper; git runs only in unconditional `x=$(git ...)` assignments, so a git failure reaches the trap and exits 1.
- `open` path refusals pinned to exit 64 (missing spec, symlinked spec, whitespace, `=`, missing spec directory), checked before any git call and before canonicalization. C11a asserts exactly 64.
- DEC-N accepts one rare case: a single-pass fallback that ended NEEDS REVISION, then a verb round that closes APPROVED, rolls up `caught=false`.

## Build notes: T1a/T2a (verb + C1-C4, C11a)

Implementation-time deltas from the spec; each entry is a decision the spec did not make, or a reading picked under the fail-closed rule.

- Field layout: on a `ROUND` line the k=v pairs sit in field 4 (`TS | ROUND | <state> | token=.. ...`); `closing` then carries r6 in field 5 and summary in field 6, matching the spec's "`closing` carries them as ` | `-split fields" wording and the fields-2-to-4 resume key.
- `open` runs the spec-path refusals (64) before `unset $(git rev-parse --local-env-vars)` and before canonicalization. C11a's "before any git call" reading wins; the unset still guards every repo-touching git call after it.
- The canonical spec path is re-checked for whitespace/`=` after `pwd -P` (exit 64). A spaced or `=` ancestor can enter through canonicalization even when the raw arg is clean, and a field-4 value with a space or `=` would misparsed read-side.
- A missing `summary` defaults to `<critical> critical` for APPROVED too, not only NEEDS-REVISION; field 6 then always has content (`0 critical`) instead of a trailing empty field.
- `validate_round()` runs as `( set -E; trap 'exit 1' ERR; _vr_dispatch "$@" )`: the trap + errtrace are subshell-scoped, planned exits keep their codes, and every git call is an unconditional `x=$(git ...)` assignment.
- Deviation, flagged: `docs/FEATURES.md` was regenerated in T1a (`feature-registry.sh check --fix`). The new test file's own text bumps five incidental `test_refs` counts (`/kit:docs`, `/kit:grill`, `/kit:spec`, `/kit:start`, `ship-gate.sh`, each +1), which fails test-meta's freshness pin without it. This brief's done-criteria need run-all green, so the mechanical regen came early; no feature content was authored. Phase 2's T4 regen stays unconditional.
- Pre-existing branch failure noted while iterating: `tests/test-gate-opt-out.sh` FAIL "hook reads config: hooks/harvest.sh, harvest_sweep.py" reproduces on the clean branch baseline (stash-tested). Not caused by this change.
