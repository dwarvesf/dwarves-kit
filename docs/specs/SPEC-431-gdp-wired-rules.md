# Spec: the kit's implicit state machines as proven gdp-wired rules, held to the bash, with the broken ones fixed

Generated: 2026-11-25
Status: VALIDATED
Lane: full (the build edits gates and hooks that block pushes and destructive commands: `hooks/safety-gate.sh`, `hooks/ship-gate.sh`, `lib/gate/lane-data.sh`, `lib/gate/dispatch-gate.sh`, the queue and the merge path)
Depth: blind-spot (failure: a fix to a blocking gate lets through something it used to refuse, or refuses a push it used to allow, on a path no example test covers)
Type: spec-feature
File: `docs/specs/SPEC-431-gdp-wired-rules.md`
References: `lib/rules/README.md`, `lib/rules/*/FINDINGS.md`, `docs/reference/hard-rules.tsv`, `docs/guides/gates-and-proof.md`, `docs/guides/autonomy.md`, `commands/execute.md` ("Routing"), ADR-0019 and ADR-0030 (disjointness), ADR-0022 (single writer), gdp-wired 0.59.0.

## Problem

The kit's promises are state-machine claims: "a fix loop stops after two tries and asks you", "never push straight to a default branch", "a quarantined slug is never launched", "a claim never takes over another session's goal". They are held by prose and by example tests, and an example test only checks the runs someone thought to write.

Two gaps follow:

- Some promises have no code at all. The verification pipeline's two-retry cap is pseudocode in `commands/execute.md` that the model is asked to follow.
- Some promises are broken in code no example reached. This spec found 30 such defects, among them: 17 destructive commands that passed `hooks/safety-gate.sh`; `hooks/anti-rationalization.sh` reading a field Claude Code does not send, so it never fired; a run lowering its lane below the spec header through the plain `override` verb; `dispatch-gate.sh` proving `./**` and `a/**` disjoint; two queue conductors on one slug; a goal claim taking over another session's running goal; a missing merge state read as CLEAN by the PR gate.

## Design

- Every implicit state machine or decision the kit runs is a gdp-wired rule in `lib/rules/<area>/`, written from what the code does (file and function cited), with the laws the docs promise.
- Laws over state reloaded from disk are proven from any state; a proof counts only when `proven && checked && !assumes`.
- Each rule keeps at least one broken variant; the prover asserts it is refused.
- Each rule backed by runnable bash has a bridge: the real script in a temp sandbox beside the rule, on enumerated and seeded inputs.
- A promised law the faithful rule refutes, reproduced by the bridge on the real bash, is a bug: the bash is fixed minimally in its own style, the rule follows the fix, the old behavior becomes a kept variant, and a regression test goes into the suite that covers the script.
- A promise the code knowingly does not keep (a design choice) is recorded as a finding whose law the prover asserts stays refuted, so a later change to it is noticed.
- The retry loop gets code: `bin/verify-loop` steps the compiled proven rule (`lib/rules/verify-loop.ts`), and `/kit:execute` reports each verdict to it and does what it prints.
- Hooks stay bash (PHILOSOPHY, "Bash over binaries"). Only `bin/verify-loop` and the provers need Node 22+; `install.sh` installs the pinned gdp-wired.

## Task Breakdown

- [x] TASK-A: the retry loop as a proven rule; `bin/verify-loop`; `/kit:execute` routing; `tests/test-rules.sh`; `install.sh` step.
- [x] TASK-B: gates area (26 rules, 151 laws; 4 fixes).
- [x] TASK-C: goals, mega-goals and queue (14 rules; 6 fixes, including `dispatch-gate.sh` F8).
- [x] TASK-D: specs, board and intake (17 rules, 127 laws; 9 fixes, including the jq 1.7 `board work` crash).
- [x] TASK-E: wrap, land, session and config (18 rules; 5 fixes).
- [x] TASK-F: hooks and autonomy (25 rules; 6 fixes).
- [x] TASK-G: one prover for every area (`node lib/rules/prove.ts`), the module README, the feature registry.

## Acceptance Criteria (global)

- `node lib/rules/prove.ts` exits 0: every law of every rule proven and kernel-checked, every kept variant refused, every recorded finding still refuted.
- `node lib/rules/prove.ts --bridges` exits 0: every bridge agrees with the real bash.
- `bash tests/test-rules.sh` exits 0.
- The full suite (`bash tests/run-all.sh --all`) has no failure that master does not also have on the same host.
- Each fix's regression test goes RED with the file put back to master (negative control) and GREEN again.

## Verification

`docs/verification/gdp-wired-proof.md`: the proofs, the bridges, the full suite against a master baseline on the same box, and the negative controls.

## Not in this spec

The kept findings in each `FINDINGS.md` that are design decisions, for the maintainer: the anti-rationalization hard stop holds for one Stop only (`stop_hook_active`), which refutes "the four hard stops are never waived"; secrets-guard does not cover the Grep tool; `mega status` reads PENDING for an existing branch against a missing base; spec-status and board moves off the `next` path are silent; a debt line after payment is collected again. The prose-only machines (the autonomy dial, the `/kit:debug` 3-fix wall, the quiescence round cap, the `/kit:docs` 2-round stop) can each be wired the way `bin/verify-loop` wires the retry loop.
