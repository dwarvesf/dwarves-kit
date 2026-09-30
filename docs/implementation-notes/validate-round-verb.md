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

## Build notes: T1b/T2b (drift, void, budget, incomplete, --stale, resume; C5-C12)

Implementation-time deltas; each is a decision the spec left open or a reading picked fail-closed.

- `why=` dimensions join in fixed order `ledger,blob,head,porcelain`; ledger drift is detected first (last line != the pinned `ROUND open`), then the three repo pins. Ledger drift also prints the offending post-open lines on stderr so the lead sees the forged/foreign write verbatim.
- Spec gone at close: the round-4 `-f && ! -L && -r` guard is reused at close. A missing, symlinked or unreadable spec leaves `blob_now` empty, which lands as `why=blob` drift, never a git error or exit 1.
- Void budget: `awk` counts `ROUND void` lines and resets on `ROUND close|incomplete`; a drift with >=1 prior void since the last round-terminal appends the `ROUND void` first, then the incomplete block with reason `restart budget spent`, exit 3. The void line is written even when the budget stops the round, so the drift stays auditable.
- `_vr_incomplete_block` is the single writer for all four incomplete paths (explicit, `--stale` over open/void, resume over closing, budget stop). The skipped GATE/OUTCOME pairs and the terminal `ROUND incomplete` are byte-identical whichever path produced them.
- Resume never re-reads caller input: `close <rid> <token>` bare rebuilds verdict/counts/r6/summary from the pinned `closing` fields; `incomplete <rid> <token>` bare reuses the pinned reason (field 5 of `closing kind=incomplete`). A full-key `close` over a `closing` round exits 1 instead of re-validating; a bare `close` over `closing kind=incomplete` exits 1 (wrong sub-verb for the state).
- `--stale` over `closing kind=incomplete` keeps the pinned reason and prints `reason ignored: <given>` on stderr; over `closing kind=close` it refuses (exit 1) rather than touch a completed close's planned records.
- Idempotent writes: `_vr_w` matches an existing line on fields 2-4 (marker, gate/phase, state) anywhere after the closing line and skips the write; `GATE validate skipped` twice in one block is impossible even if a record was hand-written or a prior partial write landed.
- Ordering inside the verb: all 64 input refusals (keys, verdict/count consistency, token grammar, reason charset) run before `unset $(git rev-parse --local-env-vars)` and before the first `ledger_file` read; the ledger/state checks (exit 1) run before any repo-touching git call; every git call stays an unconditional `x=$(git -C ...)` so a git failure hits the ERR trap as exit 1 with nothing appended (drift computation precedes all appends).
- DEC-N rollup implementation (`_vr_caught`): one awk pass, bounded by `NR < closing_line`; the window start is the latest of the rid's first `ROUND open`, the latest round-terminal `close verdict=APPROVED|incomplete`, and the latest `GATE validate ran`; a hit is an `OUTCOME <ph> end` with `caught=true` while inside a `closing`..next-`ROUND` block. The `inblk` flag is what keeps a stray lone `end caught=true` and a fallback `record+outcome` pair out of the count.
- Test-only choices: C10d hand-writes the `closing` line plus one GATE record to fake the crash (DEC-J); the git-failure leg shims `git` on PATH (exit-1 stub) instead of breaking the fixture repo; the C12 fixture ends on `ROUND close` so the last-timestamp readers (`history`, `report.run_summary`, `events.ledger_to_events`, `dashboard.collect_runs`, lane-telemetry `last`) move while every marker-keyed reader stays byte-identical. `proof-table-gen` rendered output embeds the ledger path, so the C12 comparison normalizes the log dir before `cmp`.
- `docs/FEATURES.md` regenerated again alongside T2b: the grown test file bumped the same five `test_refs` rows; same mechanical `check --fix`, still no authored content (T4 stays the Phase 2 regen).

## Repair pass: part-A review fixes

Three review lenses flagged the verb and its tests. Every fix was shown red against a deliberately broken build before acceptance (break, run the case subset, restore, re-run green); the red lines live in `docs/verification/validate-round-verb.md`. No review item conflicted with the spec.

Code changes, all in `lib/gate/gate-ledger.sh`:

- `_vr_check_resume` (new) is the resume guard: the lines after a round's `ROUND closing` must be a strict normalized PREFIX of that round's planned records (the full planned line minus timestamp via `_vr_norm`, not fields 2-4). Foreign lines print via `_vr_print_foreign` (`  foreign: ` prefix, control bytes stripped with `LC_ALL=C tr -d '\000-\010\013-\037\177'`) and the resume refuses with exit 1, ledger untouched. Both resume paths (`_vr_close_records`, `_vr_incomplete_block`) call it. Red proof: neutering the guard to `return 0` fails all six C10d forged legs (exit-1, stderr naming, byte-identical ledger, for close and incomplete resumes).
- `_vr_porcelain <top>` extracted (the duplicated status|hash-object pipeline); `_vr_load <rid>` extracts the ledger/last-line/state/field-4/token prelude; `_vr_refuse_ctl <name> <value>` extracts the `\n`/`\r`/`|` refusal; `unset $(git rev-parse --local-env-vars)` moved into `_vr_dispatch` so every sub-verb gets it once. Red proofs: removing the dispatcher unset fails the C1b `gitdir`/`gitcommon` legs (6 red); appending `|| echo broken` to the porcelain pipeline fails the git-status shim legs (open exits 0, close writes records).
- `awk -v o="$last"` became `VR_O="$last" awk '... $0==ENVIRON["VR_O"] ...'`: `-v` escape-processes `\t`/`\n` in the value, so a path like `x\ty` made the open line never match and `close` listed the round's own records as "foreign". Reproduced on a repo under a literal `x\ty` directory: under `-v` the whole ledger prints as foreign; under `ENVIRON` only the real foreign line prints.
- `open` canonicalizes with `CDPATH= cd -- "$sdir"` (was bare `cd`), then re-runs `-f`/`-L` on the canonical path and re-checks the canonical path for whitespace/`=`. Demonstrated: with the `CDPATH=` prefix removed, `env CDPATH=<decoy>` + a relative spec arg makes `cd` echo the resolved dir, `spec_dir` becomes two lines, and the canonical charset recheck refuses 64 (fixed build: exit 0). The canonical `-f`/`-L` recheck sees the same inode as the pre-check in every reachable case; kept as defense-in-depth after the pwd -P resolution.
- `incomplete` refuses an empty reason with 64 on both the explicit-token and `--stale` paths. Red proof: the check removed gives rc 0 (explicit) and rc 1 (`--stale`) on the C11b legs.
- `local cd` renamed to `caught_dr`: `cd` shadowed the builtin inside `_vr_close_records`, and any later `cd` call in that scope would read oddly.

Test changes, `tests/test-gate-validate-round.sh`:

- Top of file: `unset $(git rev-parse --local-env-vars)`, `HOME` pinned to a `mktemp -d`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_CONFIG_NOSYSTEM=1` -- an exported `GIT_DIR`/`GIT_COMMON_DIR` or a user-global gitconfig can no longer steer the fixture repos.
- C11a charset legs create the offending files first, so only the charset rule can produce 64 (was: `-f` refusal could answer first). Red proof: the charset `case` neutralized gives rc 1 (ship-glob mismatch), not 64, on both legs.
- C11a "raw slug survives normalization" uses a spec named for the raw slug with rid=`runid(slug)`, so only the raw-vs-runid check can refuse. Red proof: neutered check lets open exit 0.
- Git-failure shims (`gitshim <subcmd>`) fail exactly one git subcommand with 128 and pass the rest through; all six legs (hash-object/rev-parse/status x open/close) assert exit 1, never 128. Red proof: `trap 'exit 128' ERR` turns all six legs red; the `|| echo broken` porcelain mutation turns the two status legs red separately.
- C11a also closes with the forged token text (the ROUND-shaped string planted inside a GATE reason) and asserts the ledger is unchanged. Red proof: self-comparing the token check turns the forged-token and stale-token legs red.
- LOWs folded: C1c captures the second open's real rc (was `$?` of a trailing assignment, which can never fail; red-proofed by making `void` a refusal state in open, three legs red); C1b adds a foreign-repo cwd leg plus a dirty spec and asserts `cat-file -e` in the spec repo per leg; C5 runs `cat-file -e` right after open (red: `hash-object` without `-w` drops three legs); C8b/C9 assert the first close exits 2 (red: `exit 2` -> `exit 0` drops five drift legs); C10c/C10d assert the full incomplete block, not one line (red: `caught=false`->`caught=true` on the incomplete writer drops four block legs); BSD `sed -i ''` replaced by `sed > tmp && mv`.
- C12 fixture is dated `$(date -u +%Y-%m-%d)` so `report --period month` sees it (red: pinning TSD to 2020-01-01 fails the non-empty leg), gains a `descent vr-c12 full` leg and runs `progress` with `full` (red: a `grep -c ROUND` injected into both readers fails the byte-identical legs).

## Build notes: T3/T4

Command files now drive the round through `validate-round`; each entry is a decision the spec left open or a pin moved deliberately.

- `commands/spec.md` step 5: the parallel round opens with `validate-round open <rid> <spec path>` (prints the `<token>`; readable back from the last `ROUND` line of `show <rid>`), closes with `validate-round close <rid> <token> verdict=... r6="..."`, and ends dead rounds with `validate-round incomplete <rid> <token> "<reason>"` or `incomplete <rid> --stale "<reason>"`. The shared exit rule is stated once ("Round exits, one rule for every sub-verb"): 0 proceed; exit 2 is `close`-only and re-opens via a fresh `open`; exit 64 wrote nothing and allows one corrected re-run of the same sub-verb; 1, 3 and any other non-zero stop and report. Void stderr lines are named untrusted data. Reviewers run no command that writes into the worktree and keep repro/scratch in a copy under `$TMPDIR`; consumer-repo tools writing untracked, non-ignored files void the snapshot. No spec, worktree, commit or Status edit between `open` and a `close` that exits 0; the fold happens only after that.
- The single-pass fallback sentence keeps the literal manual records the emit sweeps pin: `gate-ledger.sh outcome <rid> Validate start|end` and `design-record start|end` plus the `record` forms, unchanged.
- `commands/execute.md` preflight: the "last validate is ran/override" test now parses by field, `awk -F' [|] ' '$2=="GATE" && $3=="validate"{s=$4} END{exit !(s=="ran"||s=="override")}'`, because a later `action`/`record` line whose free text carries ` | GATE | validate | ran | ` fools the old grep. The meta pin that named the old grep was updated in the same commit (`tests/test-meta.sh`, "field-parsed last-line-wins validate read"). The dispatch and critical-stop paths use the verb; an `incomplete --stale` there is a stop, never a re-open; any critical still stops before task 1 and asks the operator.
- `commands/wrap.md` step 10: the lead opens the round under the worker's rid and spec path (`open` binds the rid to the spec branch's slug, so a wrong rid refuses) and closes it with the full-key `close`. `--stale` is a stop, not a re-open; the item stays `REPORTED`. `VALIDATE PENDING`, `SendMessage` and `fresh builder` survive verbatim; the old self-run validation wording is gone; worker/lead separation and the no-main-checkout rule are unchanged.
- T4: `bash lib/registry/feature-registry.sh check --fix docs/FEATURES.md` ran unconditionally; reports `docs/FEATURES.md is fresh`, no diff written, so T4 carries no commit of its own.
- Iteration note: `bin/test-affected` defaults to a 300s per-suite timeout, which kills `test-wrap.sh` (~15 min), `test-meta.sh` (~6 min) and `test-hooks.sh` (~5 min) mid-run; `TEST_AFFECTED_TIMEOUT_SECS=1800` passes all three. The only standing failure is `test-gate-opt-out.sh` ("hook reads config: hooks/harvest.sh, harvest_sweep.py"), already red on the branch baseline per the T1a/T2a note.
