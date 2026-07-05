# ADR 0010: a deterministic signal-marker pre-gate before the reviewer model call

**Date:** 2026-07-02
**Status:** accepted

## Context

The reviewer pays for a `claude -p` (haiku) call on every substantial session, then the model
decides whether a reusable skill fired and returns `{draft:null}` when nothing did. `null` is the
common outcome (the prompt biases hard toward high precision), so a large share of the spend buys a
"nothing to save" verdict the model could often have been spared. The single-flight lock (ADR 0004)
bounds concurrency, not per-session waste. There was no cheap pre-filter to skip the obviously
signal-free sessions before the model runs.

## Decision

Add a deterministic pre-gate in `reviewer-run.sh`, between the empty-transcript check and the lock:
if `signal_gate` is on AND the compacted summary contains none of a broad set of signal markers
(user correction / frustration, a fix / technique / debug path, a skill-was-wrong note , mirroring
the prompt's signal list), skip the model call and ledger `skip-no-signal`. The marker regex is one
`grep -qiE` in `has_signal_markers()`, overridable via `signal_markers` / `CC_SI_SIGNAL_MARKERS`.

The gate is **default OFF** and the pattern is deliberately **broad** (biases toward keeping a
session). A false positive only wastes one null-draft call; a false negative drops a real signal (a
lost skill), so the gate is tuned to under-skip. Skips are ledgered so the false-negative rate is
auditable before the gate is trusted and flipped on.

## Alternatives considered

- **Let the model keep judging every session (status quo).** Rejected as the thing being improved,
  but it IS the default until `signal_gate` is enabled, so no behaviour changes on upgrade.
- **A model-based cheap classifier before the real reviewer.** Rejected: it reintroduces the very
  model call the gate is meant to avoid, only smaller.
- **Raise `transcript_k` / disable the skill (the knobs SPEC-103 already lists).** Those trade
  quality or turn the feature off wholesale; the gate is finer-grained.

## Trade-offs

A keyword heuristic cannot see signal type "a non-trivial technique emerged" when it surfaces
without correction/frustration/fix vocabulary, so an aggressive pattern would drop real skills.
Accepted by making the gate opt-in, the pattern broad and overridable, and every skip ledgered for
audit. The precision-critical default (model judges) is preserved until the operator opts in. The
recall guard is tested per marker CATEGORY (correction, frustration, technique, fix, debug,
skill-patch) so a regex regression on one half of the pattern is caught, not masked.

The skip path's `_ledger` call is the first ledger write that runs BEFORE `si_acquire_lock`, so two
concurrent marker-free sessions can append to `ledger.jsonl` (a bare `>>`) without the single-flight
lock serializing them. Accepted, not fixed: each row is one line well under `PIPE_BUF` and O_APPEND
makes such writes atomic on APFS; taking the lock before the gate would pay lock-acquisition cost on
every skip and defeat the point.

## Open questions

- The right long-run default (keep OFF, or flip ON once the ledger shows an acceptable skip
  precision) is left to an audit of `skip-no-signal` ledger lines against a manual re-review.
  `cc-improve status` breaks out `gate-skips (7d)` from real `reviewer runs (7d)` to make that
  audit legible (a skip is a 0-cost row, so it never distorts the spend line).
