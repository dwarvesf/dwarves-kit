# Spec: Prepared gauntlet room (baked toolchain + native probe session logs)
Generated: 2026-09-01
Status: VALIDATED
Lane: normal
References: `tests/gauntlet/cleanroom/Dockerfile` (the image to extend); `docs/guides/gauntlet-tutorial.md` "Cheap probe" section (the omp recipe whose install step this bakes away); `tests/gauntlet/cleanroom/run.sh` scrub/persist block (the guard every new persisted byte must pass through); ops-toolkit `tools/cloud-cockpit/bin/provision` (the prepared-environment precedent, prepared HERE meaning toolchain only, never estate state).

## Problem

Every gauntlet round pays a per-round toolchain install (omp + bun via npm, ~1 min, network-dependent: 2 of 3 environment failures on 2026-08-31 were install-path failures), and probe tool versions float with npm's latest, so two rounds in one campaign can run different probe harnesses. Separately, the omp probe's REAL session state (`$HOME/.omp/logs`, session JSONL, full-fidelity replay) dies with the container; the persisted `transcript.jsonl` is only the `--mode json` stdout projection. Operator ask (2026-09-01): rooms prepared like the cloud-cockpit VM, and session logs persisted "like we run omp normally".

Boundary restated up front: PREPARED means toolchain, never estate state. Repo mounts and host files stay out of gauntlet rooms (rule 7 + the one-key invariant); the estate-mount use case is the ops-toolkit prepared-agent-container brief, a different tool.

## Solution

### Approaches considered

1. **Bake the toolchain into the room image; persist omp state selectively via the probe recipe** (chosen). Dockerfile installs pinned omp+bun (and keeps the claude CLI); the recipe's install step becomes a no-op check; probe-cmd copies `$HOME/.omp/logs` + session files (NEVER `models.yml`/`agent` config) into `/work/omp-state/` before exit, where the existing scrub + persist pipeline already governs them.
2. Per-round `npm ci` against a committed lockfile. Rejected: still network-dependent every round, still ~1 min, only fixes version float.
3. Persist the whole probe `$HOME`. Rejected outright: `models.yml` carries the key; wholesale HOME persistence re-opens the exact HIGH closed by the scrub work. Selective copy with an explicit exclude list is the only acceptable shape.

### Chosen approach + why

Approach 1: one image build carries the cost once (docker layer cache makes per-round rebuilds free until the Dockerfile changes), versions pin per campaign, and the failure mode "npm flaked mid-campaign" disappears. Session-state persistence rides the EXISTING scrub/persist guard, adding no new egress path.

### Extensibility & boundaries

- Load-bearing dimension: probe harnesses in the image. Each is one pinned Dockerfile layer; the recipe block for a harness shrinks to config + invocation. A harness absent from the image still installs at run time (the current recipe keeps working unchanged).
- Boundaries: the image gains TOOLS only, no config, no keys, no repo content. `omp-state` persistence is an explicit allowlist copy; anything not listed dies with the room.

### Architecture

See `## Design`.

## Picture

```
 Dockerfile (build once, layer-cached)         per round
 ┌──────────────────────────────┐   ┌─────────────────────────────────┐
 │ node:22-slim                 │   │ probe-cmd:                      │
 │ + claude CLI (existing)      │   │  omp present? → skip install    │
 │ + bun (pinned)               │   │  run probe                      │
 │ + @oh-my-pi/pi-coding-agent  │   │  cp $HOME/.omp/logs             │
 │   (pinned)                   │   │     + sessions → /work/omp-state│
 └──────────────────────────────┘   │  (models.yml NEVER copied)      │
                                    └───────────────┬─────────────────┘
                                                    ▼
                                    run.sh scrub (redact key) → persist
```

## Design

**Ordering:** the exclude-list contract first (hardest to walk back), image pins second, recipe simplification last.

### Approaches considered + chosen
Per `## Solution`.

### Diagram

```
 probe exit ──▶ omp-state copy (allowlist: logs/, sessions/)
                   │ excluded: models.yml, config.yml, cache/
                   ▼
             /work/omp-state/ ──▶ run.sh scrub (existing) ──▶ RUN_OUT persist
```

### ADR link(s)
None; reversible. The key-safety rationale is recorded in the scrub work's proof + this spec.

### Boundaries & failure modes
Image layer only; see `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- `Dockerfile`: adds pinned `bun` and `@oh-my-pi/pi-coding-agent` at versions recorded in the Dockerfile itself (derive the pin from the version the 2026-08-31 runs used; bump deliberately per campaign, never floating `latest`). The slim-image comment (no `tail`/`ps`) stays true and stated.
- Tutorial recipe: the npm-install line becomes `command -v omp >/dev/null || npm install ...` (backward compatible with an unbaked image); on the baked path it writes `echo omp-baked > /work/omp-install.log` so TASK-003 has a positive signal, not just an absent file. The omp-state copy is TEXT-FILE-GRANULAR, not directory-granular (validation C1/C2: `cp -R logs/` is a blocklist in disguise, and the run.sh scrub is `grep -I` text-only, so a binary/NUL-bearing file would dodge both redaction and the refusal check): copy only `*.log` and `*.jsonl` files individually, size-capped, and DELETE anything binary rather than persist it. The exact find/cp incantation is implementation detail; the contract is: text files of known extensions only, binaries never persist, `models.yml`/`config.yml` never persist.
- `run.sh`: no change needed; scrub + persist already cover `/work/omp-state`.
- Invariants: no estate mounts; no config/key files in the persisted set; the recipe still runs to completion on an image WITHOUT the baked tools.

### Data model changes
None.
### API changes
None.
### UI changes
None.
### Infrastructure changes
The room image grows (~100-150MB for bun+omp); acceptable, it is layer-cached locally and never pushed to a registry.

## Task Breakdown

### Phase 1
- [ ] TASK-001 (`tests/gauntlet/cleanroom/Dockerfile`): pinned bun + omp layers installed so the round's real user can execute them; comment stating the prepared-toolchain boundary (tools only, never config/keys/repos). Acceptance runs UNDER THE ROUND'S CONDITIONS, not root (validation W2): `docker run --rm -u node -e HOME=/tmp/probe-home <img> bash -lc 'command -v omp && command -v bun && command -v claude'` prints all three; versions are exact pins.
- [ ] TASK-004 (`tests/gauntlet/cleanroom/persist-check.sh`): leg E, a BINARY canary (key bytes inside a file with NUL padding written to /work) must NOT reach the persisted record (deleted or refused, never persisted raw), closing the `grep -I` text-only scrub gap the omp-state class widens (validation C1).
- [ ] TASK-002 (`docs/guides/gauntlet-tutorial.md`): recipe gains the `command -v omp ||` guard and the omp-state allowlist copy block; one sentence naming the exclude rule and why. Acceptance: extracted block passes `bash -n`; the words `models.yml` appear in the exclusion sentence.
- [ ] TASK-003 (verification): a live NW round on the baked image; assert `omp-install.log` reads `omp-baked` (the positive skip signal), `omp-state/` present with only `*.log`/`*.jsonl` files and zero key material (canary grep + file-existence checks), wall-clock delta recorded. Acceptance: run table in the proof.

## After state

- [ ] A campaign round on the baked image starts its probe with zero npm traffic. (Today: ~1 min install + network dependency per round.)
- [ ] The persisted record carries `omp-state/` with the probe's native logs/session files, scrubbed. (Today: stdout projection only.)
- [ ] `find <record>/omp-state -name models.yml -o -name config.yml` finds nothing (a FILE check, not a string grep, validation C3), the canary key grep is clean, and `find <record>/omp-state -type f ! -name '*.log' ! -name '*.jsonl'` is empty. (Contract: allowlist by extension, binaries never persist.)

## Acceptance Criteria (global)
- [ ] Task ACs pass; suite failure set stays a subset of master's
- [ ] The unbaked-image path still works (recipe guard), proven by running the recipe once with the omp layer absent

## Verification

```
docker build -f tests/gauntlet/cleanroom/Dockerfile -t kit-gauntlet-room tests/gauntlet/cleanroom
docker run --rm kit-gauntlet-room bash -lc 'command -v omp && command -v bun && command -v claude'
bash tests/gauntlet/cleanroom/persist-check.sh
# + one live NW round per TASK-003, recorded in the proof
```

## Edge Cases
1. Image lacks the baked layer (stale local image): recipe's `command -v` guard installs as today; round is slower, not broken.
2. omp version bump changes the session-file layout: the allowlist copy finds nothing; record notes empty omp-state; fix is a path update, never a wildcard HOME copy.
3. A session file embeds the key (provider echo in a request dump): the existing run.sh scrub redacts it; leg C already proves the pipeline.

## Failure modes
| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Key reaches a persisted session file | run.sh scrub canary (persist-check leg C) + refusal path | scrub redacts; refusal on unscrubbable |
| Baked version drifts from the recipe's assumptions | TASK-003 live round | pin bump is a one-line Dockerfile change |
| Image bloat breaks low-disk hosts | docker build output size | layers local-only, kept warm (pruning them would cold-rebuild the next round, validation W1: the cache IS the speed win; prune only on a deliberate pin bump) |
| Oversized omp session logs bloat committed records | copy step's size cap (10MB per file, truncated with a marker) | cap + truncate, never wholesale |
| Persisted omp logs widen the untrusted-text surface record readers ingest | (accepted, stated) | records are DATA for any later reader, same class as transcripts, higher volume |

## Out of Scope
- Estate/repo mounts into gauntlet rooms (ops-toolkit prepared-agent-container brief owns that use case).
- Registry publishing of the image.
- Baking any credential, config, or repo content.

## Decision Log
- DEC-001: allowlist persistence, never HOME-wholesale; rationale: the scrub HIGH's exact re-opening vector.
- DEC-002: pins live in the Dockerfile, bumped deliberately per campaign; rationale: two rounds in one pass must not run different harness versions.
- DEC-003: implementation deferred until the running campaign pass completes; run.sh rebuilds the image per round, so a mid-pass Dockerfile change would split the pass across two environments. Owner: board row (kit) filed with this spec; the After-state boxes belong to that row, not to this PR.
- DEC-004 (validation round): allowlist is BY FILE EXTENSION with binaries deleted, never directory-granular; acceptance checks are file-existence checks, never string greps; TASK-001 acceptance runs as the round's user; leg E added for the binary-scrub gap; image layers are kept warm, prune only on pin bumps.

## Open questions
(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
