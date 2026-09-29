# Implementation notes -- lane-bug-machinery

Deltas from SPEC-362. Nothing here repeats what the spec already states.

## 2026-09-29 The bug-lane review and debug gates are advisory without a spec
- Context: `hooks/ship-gate.sh` exits 0 at the spec lookup when no `docs/specs/SPEC-*-<slug>.md` exists. A bug-lane run usually has no spec.
- Decision/Change: none. The lane-gate check (build, review, debug) is not hook-enforced for a spec-less run; that is true for every bug-lane run today.

## 2026-09-29 Side effect during grounding
- Running `lane-classify.sh check bug --files lib/wrap/wrap.sh ...` for the round-0 grounding appended one `LANE-CHECK | downgrade` line to the operator's `completeness.log`. That line is a grounding artifact, not a real run. It stays in the log, by the lead's instruction. Rounds 2 and 3 grounded through scratch prototypes and wrote no log.

## 2026-09-29 Lead decisions, round 0 (pre-validation)
- (a) Accepted: a spec-less bug-lane machinery fix is held only by the proof gate, the same as every other bug-lane fix. Still holds in round 3, with the round-2 finding that the proof gate itself defaults off (below).
- (b) Contract beats tiny. Still holds in round 3, now restricted to `classify`, `explain` and `check`.
- (c) Install surfaces count as machinery. Still holds in round 3, kit repo only.

## 2026-09-29 Lead decision, round 1: enforcement-file denylist (REVERSED in round 3)
- Round 1 decided a structural guard: enforcement files never demote, defined as `_ENFORCEMENT_GLOBS` plus a text-only `_ENFORCEMENT_WORDS_RE`, with a broadened relaxation vocabulary as the second defence.
- Round 1 also decided the kit-only scope of the install and settings surfaces (Change item 7). That part stands.

## 2026-09-29 Lead decision, round 3: kit-repo-only allowlist (reverses round 1)
- Round-2 evidence (R1, R2, R3, R5 criticals, one root cause: the denylist leaks):
  - files the gates source or call were missing: `lib/config/kit-config.sh` (decides whether `proof_of_done` and `lane_gates` are on), `lib/ledger/ledger.sh`, `lib/telemetry/kit-log-dir.sh`, `lib/registry/feature-registry.sh` (ship-gate exits 2 on its check);
  - `hooks/codex-hook-adapter.sh` was in the globs but not the words regex;
  - `wrap.md:318` passes `--files` newline-separated and `_files_touch_machinery`'s `read -ra` reads only the first line, so an enforcement file in second position demoted (pre-existing bug, inherited by the guard);
  - unquoted glob splitting expanded against the cwd;
  - `gate.proof_of_done` defaults to `false` (`kit.toml:111`); it is on only through the operator overlay, so a demoted fix in a consumer repo would be held by nothing.
- Decision (lead, R5's recommendation): replace the denylist with `_DEMOTABLE_GLOBS`, demote only in the kit repo, only with `--files`, only when every path is allowlisted; drop the relaxation vocabulary; tighten `_mbug_re`; normalize FILES once; replace the enforcement-hook drift test with an allowlist drift test.
- Round-2 late block (R4) folded: a label-exact NC wrapper (negctl discards suite output), explain assertions on the demote and overrule paths, quoted pattern arrays, a missing-path row each side of the allowlist, the registry `--fix` as the last step, env exports in a subshell, `tests/run-all.sh` for AC6 (`bin/test-affected` is not on this branch's base).

## 2026-09-29 My calls inside the round-3 redesign
- Neutral paths (`tests/*`, `docs/*`, `_meta/*`, `README.md`) do not block demotion. The lead's text says "EVERY path matches `_DEMOTABLE_GLOBS`"; read literally, 112 of the 116 historical fix commits would never demote because they also touch a test, a doc or a board row. A contract file on a neutral path (`docs/WORKFLOW.md`) still forces `full`.
- Candidates dropped from the lead's list after verification: `lib/board/backlog.sh` (called by `lib/wrap/wrap.sh:111` and `lib/goal/wt.sh:41`), `lib/board/board.sh` (named in two hook docstrings, so the mechanical drift test would flag it; it also calls `backlog.sh` and `kit-config.sh`), `lib/reflect/staging-format.py` (called by `wrap.sh:110`), and the secret and credential files listed in `_DEMOTABLE_EXCEPT`. The rest of `lib/board` stays in.
- Candidate added beyond the lead's list: `lib/prose-rag/*`. Its only caller is the allowlisted advisory hook `hooks/prose-rag.sh`.
- The drift test skips callers that are themselves allowlisted (context-hints calls context-readiness; session-state-save names slop-cleaner) and ignores `hooks.json` wiring, which registers hooks rather than calling them.
- `_bug_core` is shared; step 4 keeps `repro` by appending it (`"$_bug_core|repro"`), so step 4 is unchanged while the machinery signal drops bare `repro` per R3.
- Prototype pitfalls the build must avoid: sourcing `lane-classify.sh` turns on `set -euo pipefail` in the sourcing shell; a regex starting with `-` needs `grep -e`; this shell has `noclobber` set, so scratch overwrites use `>|`.
