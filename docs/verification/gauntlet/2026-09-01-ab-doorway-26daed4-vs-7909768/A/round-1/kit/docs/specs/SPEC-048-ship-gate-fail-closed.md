# Spec: ship-gate lane arm fails closed on spec-exists-no-lane

Status: DRAFT
Lane: full

## Problem

`hooks/ship-gate.sh`'s lane arm fails OPEN at line 61: when a spec for the branch slug exists but
declares no `Lane:` header, it `exit 0`s instead of blocking. So a spec-driven change can ship
without its lane's gates ever being checked. This is half of the growatt-tui gap (the other half,
no per-repo contract, is sub-goal 01 / `/kit:adopt`). Separately, `install.sh` only prints a
manual `cp AGENTS.md` tip nobody runs; now that `/kit:adopt` exists it should route through it.

## Design

Two surgical changes:

1. **Fail closed on spec-exists-no-lane, in an adopted repo only.** At `ship-gate.sh` line ~61,
   when `$SPEC` exists but `$LANE` is empty: if the repo has the proof marker
   (`docs/verification/README.md`, i.e. it adopted the kit), BLOCK (exit 2) with a message naming
   the spec + how to classify a lane. Otherwise keep failing open. Everything else (no spec at
   all, no marker, missing ledger) stays fail-open: the gate can never block unrelated work.
2. **install.sh routes adoption through `/kit:adopt`.** Replace the `cp $KIT_DIR/AGENTS.md
   ./AGENTS.md` tip with a pointer to `bash lib/adopt.sh <repo>` (or the `/kit:adopt` command).

## Scope

**In:** the `$LANE` empty branch of `hooks/ship-gate.sh`; `tests/test-ship-gate-fail-closed.sh`;
the install.sh adopt tip.
**Out:** the proof-of-done arm (already fails closed correctly); the adopt command (sub-goal 01);
any consumer repo (sub-goal 03).
**Not:** changing `safety-gate.sh`, push-to-main handling, the proof-class logic, or the
lane->gate matrix; adding new required gates; enforcing under non-CC runtimes.

## Acceptance criteria

- [ ] Crafted-stdin `git push` through `ship-gate.sh` returns **exit 2** when: proof marker
  present + a spec for the slug exists + the spec has no `Lane:` header.
- [ ] Returns **exit 0** when the spec has a `Lane:` and its required gates are recorded.
- [ ] Returns **exit 0** (fail open) when: no proof marker, OR no spec for the slug, OR the
  command is not a `git push`/`gh pr create`.
- [ ] `install.sh` references `adopt` (no longer the bare `cp ... AGENTS.md` tip).
- [ ] `bash tests/test-ship-gate-fail-closed.sh` passes; `bash tests/test-meta.sh` stays green.

## Test plan

| Scenario | stdin | repo state | expect |
|---|---|---|---|
| spec, no lane, adopted | git push | marker + SPEC-*-<slug> w/o Lane | exit 2 |
| spec, lane, gates recorded | git push | marker + SPEC w/ Lane:full + ledger full | exit 0 |
| spec, no lane, NOT adopted | git push | SPEC w/o Lane, no marker | exit 0 |
| no spec | git push | marker only | exit 0 |
| non-push command | git status | anything | exit 0 |

Behavioral proof: a recorded run of the blocked case (exit 2) + the negative control (add a Lane
or remove the marker -> exit 0).

## Edge cases

1. Spec has `Lane:` but an unknown value -> the existing `check <lane>` path reports "unknown
   lane" and blocks (already handled; not in scope to change).
2. Proof marker present but no `docs/specs/` dir -> no spec found -> fail open (line 59).
3. Multiple specs match the slug -> `head -1` (existing behavior, unchanged).

## Resolved decisions (during build)

- (append during build)
