# SPEC-230: Gauntlet cloud runner, Claude Code remote environments as a first-class runner option

**Status:** SUPERSEDED / WILL-NOT-BUILD (spec-validate round 2 R6 PASS, but P0
platform verification FAILED 2026-08-10). This spec is a design record kept for
its findings; the cloud runner it designs is NOT buildable and will not be
built. Root cause: Claude Code cloud environments are a HUMAN launch mode (TTY
/ claude.ai web / mobile), not a programmatic dispatch target. All three cloud
routes were tested and failed for automation: `Agent(isolation:"remote")`
resolves to a LOCAL worktree (P0.1, P0.2); `claude --cloud` refuses `--print`
and piped stdin, TTY-only (P0.3). Evidence: `docs/verification/gauntlet/
2026-08-10-p0-cloud-dispatch/P0-RESULT.md`.

**Decision (final):** gauntlet/queue runners stay `local` + ssh-alias (the Mac
Mini, proven this session). No `runner_host = "cloud"`. The one durable win
that fell out of this spec, the root-only config read for `runner_host` /
`probe_key_ref`, shipped independently as #377. The follow-up worth doing is
NOT a cloud runner but moving PR-open to the authed client (ID-472). Do not
reopen this spec to build Approach A; if a scriptable cloud-launch API ever
ships, that is a NEW spec with its own P0.
Lane: full
**Backlog:** ID-471. **Relates:** SPEC-226 (telemetry unchanged), SPEC-227
(campaign shape unchanged; supplies the batch workload for the acceptance
checker), SPEC-229 (checker-first rounds). **External reference:** ops-toolkit
`research/2026-08-10-cc-remote-environments.md`.

## Problem

Gauntlet rounds run through `tests/gauntlet/cleanroom/run-remote.sh`: local
Docker room, or ssh-shipped to the Mini. This occupies the Mini, needs
Docker/colima and ssh, and the room sits on a host with ambient state one
layer out. Claude Code cloud environments offer on-demand VMs with zero
persistence and a fresh clone per session. Cloud should be a third
`runner_host` value, with local and the Mini staying selectable.

## Picture

```
 ORCHESTRATOR (local session, /kit:gauntlet)
 +--------------------------------------------------------------+
 | Tier 1 suite -> green?          kit-root kit.toml            |
 |      |                          [gauntlet.cloud_envs]        |
 |      | yes                      repo-url -> environment ------+--> /remote-env
 |      v                                                       |    (campaign start,
 | push surface SHA ---------------------------------------+    |     readback-verified)
 |      |                                                  |    |
 |      v                                                  |    |
 | Agent(isolation:"remote", model:sonnet, nonce N) -------+----+--------+
 |                                                         |    |        v
 | fetch transport branch <--------------------------------+ +--------------------------+
 |      |  refuse unless manifest: nonce, env, SHA, model  | | CLOUD VM = the room      |
 |      v                                                  | |  setup: depth-1 reclone, |
 | SANDBOXED checker re-run (docker cleanroom image)       | |  prune answer key,       |
 |      |  never the bare host                             | |  print ROOM-READY        |
 |      v                                                  | |  probe runs AS session   |
 | score -> persist record -> delete transport branch      | |  push gauntlet/run-* br  |
 +--------------------------------------------------------------+  (fallback: inline     |
                                                             |    report if push fails) |
                                                             +--------------------------+
```

## Approaches considered

| Approach | What it is | Why / why not |
|---|---|---|
| A. Cloud remote-agent (CHOSEN) | probe dispatches as `Agent(isolation:"remote")`; the VM is the room | Purest host-state isolation, zero probe secrets, no infra to own, phone-startable. Costs: plan-pool billing (no spend-capped key), permission-posture differences, two platform unknowns (P0), branch transport needs hardening. |
| B. Ephemeral CI runner (gh-hosted runner or throwaway container) | `gh workflow run` builds the room, runs `claude -p` probe with the spend-capped key, uploads artifacts | Keeps spend-capped key, documented base image, artifact channel replaces branch transport, works headless. Costs: CI infra to own per target repo, minutes billing, secrets (API key) enter CI, slower spin-up, not phone-native. Strong runner-up; revisit if P0 fails. |
| C. Extend ssh path to a rented VM (Vultr etc.) | run-remote.sh, host = cloud VPS | No new dispatch model, but owns infra + secrets on the VPS and gains nothing over the Mini except capacity. Rejected. |

Chosen: A, on the axes Han optimizes for (zero owned infra, zero probe
secrets, phone-startable, dogfoods the platform). B is the named fallback if
P0 proves A unbuildable.

## P0: prerequisite verification (build gate, before any delta row)

Two platform assumptions are load-bearing and unverified. Each gets a tiny
scripted probe with a recorded transcript in `docs/verification/gauntlet/`;
a P0 failure stops the spec and routes to Approach B.

| # | Assumption | Probe | Pass criterion |
|---|---|---|---|
| P0.1 | A headless `claude -p` orchestrator can dispatch `Agent(isolation:"remote")` (queue runs use `claude -p`, and `/remote-env` is a slash command a headless run cannot issue) | one `claude -p` script dispatching a trivial remote agent | remote agent runs; env selection controllable (or documented interactive-only limitation accepted + fail-closed guard designed) |
| P0.2 | A remote agent dispatched from a session in repo X can operate on TARGET repo Y at a pinned SHA (cloud sessions bind to the session's repo) | dispatch a remote agent told to clone/checkout a second repo at a SHA and report | target repo reachable at pinned SHA; if environments are repo-bound, the `cloud_envs` map re-keys repo->environment and the tenant framing is rewritten |

## Design

### D1. Config: third knob value + root-only reads (closes a pre-existing hole)

```toml
[gauntlet]
runner_host         = "cloud"     # local | <ssh-alias> | cloud
max_parallel_probes = 3           # campaign fan-out cap (single-tenant per campaign)
probe_key_ref       = "op://..."  # local/ssh rounds only

[gauntlet.cloud_envs]             # canonical origin URL -> environment; FAIL CLOSED on miss
"github.com/dwarvesf/dwarves-kit" = "gauntlet-dwarves"
"github.com/tieubao/*"            = "gauntlet-personal"
```

- `lib/config/kit-config.sh` gains `kit_config_get_root` (skips the project
  overlay). `runner_host`, `probe_key_ref`, and the `cloud_envs` map use it.
- `run-remote.sh` switches its EXISTING two reads to the root accessor: a
  committed project `.kit.toml` can today redirect an ssh round to an
  arbitrary host that resolves a 1P secret there. This spec closes that
  hole, not merely avoids adding one. `GAUNTLET_RUNNER_HOST` env override
  survives (operator-controlled) but the cloud guard applies to the
  RESOLVED value.
- Map keys are canonical origin URLs (host/owner/name, glob allowed), never
  display names: repo identity, not a spoofable label, selects the tenant.
  No `default` fallback row is honored for dispatch; an unmapped repo
  refuses to dispatch.
- `bin/config explain` learns a `root-only` marker so it never reports a
  project override as winning for these keys.
- `lib/config/module-registry.md` gauntlet row gains the new keys (standing
  drift lint `tests/test-config-registry.sh` covers it).

### D2. Dispatch: orchestrator-level, human-gated at campaign start

`run-remote.sh` is bash and cannot invoke the Agent tool, so cloud dispatch
lives in `commands/gauntlet.md` Tier 2. `runner_host = "cloud"` makes
`run-remote.sh` exit 64 with a pointer, never a silent local fallback.
Before the FIRST cloud dispatch of a campaign the orchestrator shows one
human gate: target repo, resolved environment, expected spend posture,
parallel cap. Inside the campaign, rounds run ungated (the loop's existing
caps bound them); the three loop-reachable risk actions are made safe
structurally: untrusted re-run sandboxed (D5), spend halted on first
rate-limit error (D7), branch deletion restricted to `gauntlet/run-*` refs
carrying this campaign's run id.

### D3. The probe: capability honesty, posture, and prompt parity

- Cloud probes carry no exfiltratable secrets (no API key, no SA token).
  They DO hold a new capability local probes never had: GitHub write via
  the platform proxy. Required scope: the target repo only. P0.2 records
  the actual grant breadth; broader-than-target is a named risk in the
  campaign gate, not silently accepted.
- Permission posture differs from `claude -p --dangerously-skip-permissions`.
  The probe instruction states the expected posture; every stall caused by
  a permission prompt is classified `runner-artifact`, not a surface
  finding (D8).
- ONE canonical probe prompt file `tests/gauntlet/cleanroom/PROBE-PROMPT.md`
  consumed by BOTH runners (run.sh templates from it; the cloud dispatch
  inlines it). Two drifting prompts would invalidate cross-runner
  comparison.
- Model pinned via dispatch (`model: sonnet`); the probe self-reports its
  model into the manifest; a mismatch voids the round with a caveat row.

### D4. The room: parity with the Docker room, honestly scoped

- Setup script (`deploy/cloud-env/gauntlet-setup.sh`, committed; thin
  caller pasted in the environment config): replace the platform checkout
  with a `git clone --depth 1` of the target at the pinned SHA (kills
  whole-history answer-key leaks: `git show`/`log -p` have one commit),
  prune with the WIDENED glob run.sh already uses (`rm -rf tests/gauntlet`
  + `find docs/verification -name '*gauntlet*'`), commit the prune so the
  probe's `git status` is clean, print `ROOM-READY <environment-name>
  <target-sha>`.
- The room-cleanliness claim is verified by the ORCHESTRATOR, not asserted
  by the probe: manifest must carry the ROOM-READY line, the pruned-path
  proof, environment name, and SHA; absence or mismatch VOIDS the round
  (infra finding, not a surface finding).
- Scope of the "purer room" claim: HOST-state axis only. The repo's own
  CLAUDE.md/AGENTS.md load in a cloud session exactly as they would for a
  real contributor; that is signal, not contamination, and is recorded in
  ROUNDS.md inputs.

### D5. Record transport: nonce'd branch + manifest interface + sandboxed verdict

- Branch: `gauntlet/run-<runid>-<row>-round-<N>-<nonce>`; the nonce is
  generated by the orchestrator per dispatch and travels only in the
  dispatch prompt. Collision-safe under parallel probes; unguessable.
- Interface (`gauntlet-record/manifest.json` at branch root): run id, row,
  round, nonce, environment name (from ROOM-READY), target SHA, probe
  model (self-reported), probe exit code, prune proof, file list. Fixed
  layout: `submission/` (patch, PR body, verification-run log, checker
  output) + `session-log/`. The orchestrator REFUSES any branch whose
  manifest is missing, nonce-mismatched, env-mismatched, or SHA-mismatched.
- MANDATED fallback: if the push fails for any reason, the probe returns a
  compact record (manifest + patch + checker output, size-capped) inline
  in its final agent report. A completed probe run must never yield zero
  evidence.
- The verdict checker re-run happens INSIDE the existing cleanroom Docker
  image over the fetched branch, never on the bare host: probe-authored
  code (`npm test`, hooks in the patch) is untrusted input; the room-side
  green in the manifest is evidence, the sandboxed local re-run is the
  verdict. This is a decision, not an implementation detail.
- Cleanup: delete the transport branch after persisting; a documented GC
  sweep (`git push --delete` over `gauntlet/run-*` older than 7 days) in
  the guide covers orchestrator crashes.

### D6. Committed state -> PUSHED state

Rule 5 ("committed state only") becomes "pushed state only" for cloud
rounds: the reviser's surface commit is PUSHED before dispatch and the
pushed SHA recorded in ROUNDS.md; the probe's manifest SHA must match.
Without this, round N+1 silently re-tests round N-1's surface.

### D7. Billing and failure modes

| Failure | Detection | Response |
|---|---|---|
| Probe never reports (VM reclaim, crash) | orchestrator deadline = probe timeout + 10min margin | round voided as BLOCKER-class infra finding; never silent retry |
| Push fails | manifest absent from branch, fallback report present | accept fallback record; note transport degradation |
| Push fails AND no fallback | deadline + empty report | voided round, infra finding |
| Rate-limit error from dispatch | error class on Agent call | HALT campaign, honest-halt verdict; never retry-loop against the pool |
| Wrong environment | manifest env != cloud_envs row | ABORT round before scoring |
| Setup script failed | no ROOM-READY in manifest | voided round, infra finding |
| Stale surface | manifest SHA != pushed SHA | voided round, re-dispatch after push |

Billing: cloud probes bill the plan pool (the spend-capped-key property is
local/ssh-only). Structural caps: round cap, `max_parallel_probes`, probe
timeout, first-rate-limit halt. `runner=cloud` rides ROUNDS.md inputs as a
caveat row, same mechanism as the frontier-model caveat.

### D8. Cross-runner comparison is a classified diff, not a count

Findings are classified `surface` vs `runner-artifact` (permission stalls,
proxy quirks, VM reclaim). Only surface findings compare across runners.
The pilot expectation "cloud >= local" applies to surface findings only.

## Test plan

The ladder, cheap to expensive; each rung is machine-checkable and gates
the next:

| Rung | What | Checker (green =) |
|---|---|---|
| T1 config | root-only resolver + fail-closed map | unit script: poisoned project `.kit.toml` (runner_host, probe_key_ref, cloud_envs row) changes NOTHING; unmapped repo refuses dispatch; `config explain` shows root-only marker |
| T2 = P0 | the two platform probes | recorded transcripts meet P0 pass criteria |
| T3 guard | run-remote.sh cloud guard | `runner_host=cloud` exits 64 with pointer; local + ssh paths byte-identical to today (regression: existing gauntlet tests green) |
| T4 room | setup script postconditions | ROOM-READY line + prune proof + depth-1 (history absent) verified from a manifest produced by one real VM run |
| T5 transport | manifest contract | fixture branches: valid accepted; missing/nonce-mismatch/env-mismatch/SHA-mismatch each REFUSED (4 negative controls); fallback inline record accepted when branch absent |
| T6 sandbox | verdict re-run isolation | checker runs in the cleanroom image; negative control: a probe patch with a malicious `npm test` script cannot touch a host canary file |
| T7 pilot | one full round per runner, same seed card, same prompt file | both rounds produce contract-valid records; classified diff computed; surface findings cloud >= local |
| T8 ACCEPTANCE (the green checker) | batch dogfood: a few dozen real tasks (SPEC-227 scenario rows + queued #auto-eligible kit rows) dispatched through the campaign machinery, routed BOTH ways: a Mini slice (`runner_host=mini-tieubao`) and a cloud slice (`runner_host=cloud`) | a validator script walks every produced run record: manifest contract holds, scrub clean, ROUNDS.md complete, both runner slices have >=1 green round and zero silent-loss rounds (every dispatch accounted: record, fallback record, or classified void). The batch summary table is the proof-of-done. |

T8 is the operator-stated done-line: "when this finishes we can run a few
dozen tasks that trigger (1) the Mini and (2) the Claude Code remote
environment". The validator script (not prose) judges it, per SPEC-229.

## What must be built (delta)

| # | Piece | File | Done when |
|---|---|---|---|
| 0 | P0 probes + transcripts | docs/verification/gauntlet/ | both pass criteria recorded (or B-pivot decision) |
| 1 | `kit_config_get_root` + 3 root-only keys + explain marker | lib/config/kit-config.sh, lib/config/config.sh | T1 green |
| 2 | shipped defaults + registry row | kit.toml, lib/config/module-registry.md | registry lint green |
| 3 | cloud guard + switch existing reads to root accessor | tests/gauntlet/cleanroom/run-remote.sh | T3 green |
| 4a | dispatch path + campaign human gate + deadline + rate-limit halt | commands/gauntlet.md | T7 dispatch works; gate shown once |
| 4b | transport contract (branch scheme, manifest, refusal rules, fallback, GC) | commands/gauntlet.md + docs/guides/gauntlet.md | T5 green |
| 4c | sandboxed verdict re-run | commands/gauntlet.md (procedure) reusing cleanroom image | T6 green |
| 5 | setup script + paste-caller | deploy/cloud-env/gauntlet-setup.sh | T4 green |
| 6 | canonical probe prompt file consumed by both runners | tests/gauntlet/cleanroom/PROBE-PROMPT.md, run.sh | T7 same-prompt comparison valid |
| 7 | pushed-state step + SHA pinning + ROUNDS.md caveat rows | commands/gauntlet.md | T7 manifests match pushed SHA |
| 8 | T8 validator script | tests/gauntlet/validate-records.sh | T8 runnable red-first |
| 9 | docs: runner table + limits + GC sweep | docs/guides/gauntlet.md, docs/patterns/gauntlet.md | doc-drift lint green |

Manual (operator, once per tenant): create the environment at
claude.ai/code, paste the caller, set the LIMITED network allowlist
(github.com + needed registries; no 1P domains).

## Per-tenant secrets (design record, build deferred)

Unchanged from v1: environment = unit of secret separation; vault
`CloudSandbox-<tenant>` + read-only SA + token on that tenant's environment
ONLY when a probe class first needs a secret; dedicated keys, never copies;
raw SA suffices on quota math; a reachable 1P Connect is the Phase-3
escalation, built only when quota hurts.

## Decision log

- v1: initial draft (VM-is-the-room, orchestrator dispatch, kit-root map,
  zero-credential probe, branch transport).
- v2 (this): /kit:spec-validate round 1 NEEDS REVISION (18 critical).
  Added: Approaches considered (CI-runner alternative honest), P0 build
  gate, sandboxed verdict re-run + nonce'd manifest transport + refusal
  rules + inline fallback, capability-honest rewrite of "zero credential",
  origin-URL-keyed fail-closed cloud_envs, root-accessor applied to the
  EXISTING ssh reads (pre-existing hole closed), depth-1 reclone + widened
  prune + orchestrator-verified ROOM-READY, pushed-state rule, failure-mode
  table, classified-diff comparison, campaign human gate, per-row done
  conditions, and the T8 dual-runner batch acceptance checker (operator
  directive: a few dozen tasks through Mini + cloud is the done-line).
