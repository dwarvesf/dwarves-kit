# ADR 0004: atomic `mkdir` single-flight lock, not `flock`

**Date:** 2026-06-19
**Status:** accepted. **Retires the stale `flock` language in SPEC-103 and CONTEXT.md.**

## Context

The reviewer needs single-flight: if a review is already running, a second trigger must skip rather
than pile up `claude -p` calls (cost + rate-limit). SPEC-103 (lines 114, 138, 220) and
`docs/specs/CONTEXT.md` (line 9) specify `flock`. But the primary host is macOS, which **does not
ship `flock(1)`** (it is a Linux util-linux command). The spec text was written before that was
caught; the code never used `flock`.

## Decision

Single-flight uses an **atomic `mkdir` lock** (`lib/common.sh` `si_acquire_lock` / `si_release_lock`):
`mkdir` of `state/reviewer.lock.d/` is atomic on POSIX, so it succeeds for exactly one caller. The
holder writes its `pid`; a later caller that finds the lock held checks whether that pid is alive and
**steals a dead holder's lock** (crash-safe). Portable to macOS and Linux with no dependency.

## Alternatives considered

- **`flock(1)`** (the spec's original choice). Rejected: not present on macOS; would need a brew
  install on the primary host, an undeclared dependency.
- **Python `fcntl.flock` one-liner** (as cc-harvest does in-process). Rejected: this tool is
  bash-only (ADR-0008); shelling to Python for a lock is an avoidable cross-language dependency.

## Trade-offs

The `mkdir` lock can wedge if the recorded `pid` is empty/unreadable or a live unrelated process
reused that pid: the steal is skipped and reviews silently no-op. RUNBOOK incident 3 documents the
manual clear (`rm -rf state/reviewer.lock.d`). A naming wart remains: the config key is
`reviewer.lock` (a file) but the lock is the `.d` directory; the bare file never exists.

## Open questions

None. The spec/CONTEXT text is corrected to match the code as part of this ADR.
