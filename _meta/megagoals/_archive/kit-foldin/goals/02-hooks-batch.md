# Sub-goal 02: hooks-batch

**Merge policy:** auto
**Time budget:** 3-5 hours of loop work
**Proof:** run-table , each of the 4 hooks fires on a fixture stdin and produces the expected stdout/exit (one row per hook), PLUS an install-into-temp-HOME check showing all 4 wired at `~/.claude/dwarves-kit/hooks/<name>.sh` in the merged settings.json, PLUS a grep of BOTH hook manifests (`settings.json` AND `hooks/hooks.json`) asserting all 4 new hook names hit in each (they are INDEPENDENT dual registrations , direct-install reads `settings.json`, plugin-mode reads `hooks/hooks.json` , and are easy to desync; a drift ships silently). Named NCs: malformed/empty hook input does not crash (fail-open where the source tool did); `harvest` writing to its ledger handles a missing ledger path cleanly. Rung 3 for `citation-guard` + `context-hints` + `harvest` (they parse untrusted transcript / user-prompt text , a fresh-context recheck re-runs the fixture proof). COVERAGE-DELTA row.
**Design:** obvious (each hook is a straight port of an existing deterministic script into the kit's hook dir + installer wiring; the events and behaviors are fixed by the source tools)
**Depends on:** none (writes only `hooks/` + `install.sh` + `hooks/hooks.json`; disjoint from lib/ and tools/)
Model: sonnet
**Branch:** feat/kit-foldin-02-hooks
**PR base:** master

## Outcome

The 4 deterministic cc-* guard tools live in `dwarves-kit/hooks/` under function names , `backlog-stage.sh` (was cc-backlog, SessionEnd), `citation-guard.sh` (was cc-citation-guard, Stop), `context-hints.sh` (was cc-context-hooks, UserPromptSubmit , coexists with the kit's existing SessionStart `context-readiness.sh`, different event), `harvest.sh` (+ its helpers; was cc-harvest, PreCompact/SessionEnd). Each is wired into `install.sh`'s settings.json merge + `hooks/hooks.json` so re-running the kit installer registers them at the fixed path. Personal defaults (ledger paths, staging dirs) become opt-in via env, no hardcoded ops-toolkit path enters the kit.

## Quality bar

A consumer who runs the kit installer gets these hooks with zero ops-toolkit snapshot step. The hooks are agent-generic: no hardcoded `~/workspace/tieubao` path, no tenant assumption. Each keeps the source tool's fail-open/fail-closed posture exactly (a guard that blocked stays blocking; a hint that was advisory stays advisory).

## How to close the loop

Per the design note landing names. For each hook:

- Port the script into `dwarves-kit/hooks/<function-name>.sh`, dropping the `cc-` name; move any helper files alongside (harvest is multi-file).
- Replace any hardcoded personal path with an env-var default that is opt-in (empty/unset = no-op or repo-relative, never a silent write to an ops-toolkit path). Use the `--repo-root`/`_repo_root()` seam if it needs consumer config.
- Register the event in BOTH data files by hand: the ROOT `dwarves-kit/settings.json` (the actual event->command registrations `install.sh` section 2 MERGES into a consumer , install.sh only COPIES the script files + merges this file, it does NOT generate registrations, so a new hook that is only dropped in `hooks/` is NEVER wired) AND `hooks/hooks.json` (the plugin-marketplace manifest). These two must stay in PARITY (the kit's own `tests/test-meta.sh` parity-checks them); update both or the hook drifts / a test fails.
- **Also generalize `install.sh`'s skill-copy step** (currently a hardcoded single-skill copy of `get-api-docs`, NOT a loop) into a loop over `skills/*/SKILL.md` , SG-04 promotes a new top-level skill (`skill-review`) and it must actually install. `install.sh` is owned by THIS sub-goal (the only one that touches it); SG-04 just drops the skill dir, this loop picks it up. Write the loop to GLOB, so merge order with SG-04 does not matter.
- Fixture test per hook: feed a representative hook payload on stdin, assert stdout/exit. Put these under `tests/`.
- Install check: run `install.sh` into a `mktemp -d` HOME, `jq` the resulting `settings.json` to confirm all 4 hook paths present at `<HOME>/.claude/dwarves-kit/hooks/<name>.sh`; grep `hooks/hooks.json` for the same 4 names; confirm the skill-copy loop copies every `skills/*/SKILL.md` (not just get-api-docs).
- NCs: empty stdin, malformed JSON payload, missing ledger dir (harvest).

Kit-adopted: record build + review + (for the untrusted-input hooks) a recheck gate via `bash lib/gate-ledger.sh`. `lane-classify` this as `normal`.

**Done =** all 4 hooks pass their fixture rows AND the temp-HOME install shows all 4 wired, captured in `docs/proof/kit-foldin-hooks.md`; no hardcoded ops-toolkit path remains (`grep -r 'workspace/tieubao' hooks/` is empty for the new files).

## Handoff on completion

1. Flip box, record PR #.
2. HANDOFF.md: note that SG-07 must strip these 4 from `redeploy.sh` once merged.
3. DECISIONS.md: record any env-var default renamed for the kit (old cc- name -> new).
4. Report in records, EXIT.

## Scope edges

**In:** `hooks/{backlog-stage,citation-guard,context-hints,harvest}.sh` (+ harvest helpers), the ROOT `dwarves-kit/settings.json` (add the 4 event registrations), `hooks/hooks.json` (parity), `install.sh` (copy the new scripts + generalize the skill-copy step to a `skills/*` glob loop), their fixture tests.
**Out:** `lib/`, `tools/`, `agents/`, `skills/` CONTENT (SG-04 places `skill-review`; this sub-goal only makes the installer copy whatever skills exist); the ops-toolkit retire (SG-07); `cc-money-gate` (stays ops).
**Not:** merging context-hints into the existing `context-readiness.sh` (different event, they coexist , verified); adding new hook behaviors the source tools did not have; changing installer logic beyond the hook wiring + the skill-copy loop generalization.

## Where to look

`ops-toolkit/tools/cc-{backlog,citation-guard,context-hooks,harvest}/`, `dwarves-kit/hooks/` (existing shape, esp. `context-readiness.sh`), the ROOT `dwarves-kit/settings.json` (where Stop/SessionEnd/etc. registrations actually live , add yours here), `hooks/hooks.json` (keep in parity), `dwarves-kit/install.sh` (the copy + merge sections, ~167-321; discover exact lines), `tests/test-meta.sh` (the settings/hooks parity check you must satisfy).

## PR body

Land 4 cc-* guards into the kit as function-named hooks (`backlog-stage`, `citation-guard`, `context-hints`, `harvest`) + wire them into `install.sh` + `hooks.json`. Personal paths become opt-in env; no ops-toolkit path enters the kit.

Verify: per-hook fixture run-table; install into temp HOME shows all 4 wired; NCs (empty/malformed input, missing ledger). Proof: `docs/proof/kit-foldin-hooks.md`.

ROADMAP: `ops-toolkit/_meta/megagoals/kit-foldin/ROADMAP.md`.

## Notes
