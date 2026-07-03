# Implementation notes: SPEC-120 pane viewer push

Delta from the spec only; decisions the spec didn't pin, deviations, tradeoffs.

## 2026-07-03 cmux open verb: new-workspace, not new-surface

**Context:** the dispatch brief prescribed `cmux new-surface ... 'tmux attach -t <s>'`.
**Decision:** the cmux path uses `cmux new-workspace --name orch:<s> --command 'tmux attach -t <s>' --focus false`.
**Why:** verified against the installed cmux CLI: `new-surface` has no command argument at all
(only `--type/--pane/--url/--provider/...`); `new-workspace` is the verb that both creates a
terminal surface AND runs a command in it. Same one-call shape, same `--focus false` pin.
**Alternatives:** `new-surface` + `cmux send '<cmd>'` (two calls, needs the surface ref back,
and `send` types into a shell -- a worse string surface).
**Impact:** spec DEC-004 records it; the T10 pin asserts the actual argv.

## 2026-07-03 Viewer open: synchronous first, flipped to fire-and-forget by the review round

**Context:** the spec initially didn't pin sync vs fire-and-forget; the first cut was
synchronous (real open verbs return in ms, the known cmux wedge is `--focus true`-specific and
pinned off).
**Decision:** REVERSED by the architecture review (P1): the osascript sinks can block
indefinitely on a first-run macOS Automation permission dialog, and the call sits inside
`_wave_run`'s spawn loop, so a hang would stall every subsequent sub-goal with no watchdog.
Now backgrounded + `disown`ed (spec DEC-006); the success/degrade message prints from the
background subshell.
**Why disown:** `_wave_abort`'s bare `wait` would otherwise block on a hung viewer child during
an operator Ctrl-C -- the abort path must never inherit the hazard the spawn path just dodged.
**Impact:** tests poll (`wait_nonempty`/`settle`) instead of asserting synchronously; the warn
is eventually-consistent within ~1s.

## 2026-07-03 Review round: 4 lenses, 3 code fixes, 4 doc fixes

**Context:** /kit:review-team equivalent (security + architecture + test-coverage +
advisor) on the working-tree diff, per the SPEC-069 lib/-touch escalation.
**Fixes taken:** (1) pre-flight allowlist exact-token enumeration (security P2: `"cmux kitty"`
passed the space-joined membership idiom; T9 now pins it); (2) fire-and-forget exec (arch P1,
above); (3) sanitized reuse-guard key (security LOW: a raw `TMUX_SESSION` with a space would
taint the space-separated guard list); (4) T10b argv-shape tests for all six viewers incl. the
osascript argv-item property + T13 real-exec missing-binary path + T7 strengthened with a
detectable env (test-coverage P1/P2); (5) CI wires the five suites the proof cites but the
workflow never ran (advisor P1: wavefront, multiplexer, token-capture, model-routing,
spec-index); (6) ADR-0032 addendum recording the section-4 surface growth (advisor P2);
(7) README orchestrate row now names MULTIPLEXER + PANE_VIEWER (advisor P2); (8) BACKLOG
footnote pointing ID-092..099 at the ops-toolkit orchestrate-hardening mega-goal dir
(advisor P2).
**Declined:** none of the four reports' P0 lists had entries; the advisor P3 (closed-tab
re-open) is documented as spec edge case 5 instead of built (would need viewer liveness
polling).

## 2026-07-03 Reuse guard records the ATTEMPT, not the success

**Context:** "one viewer per session per run" -- spec leaves open whether a FAILED open may retry
on the next wave.
**Decision:** `_VIEWER_OPENED` appends before the exec, so a failed open never retries this run.
**Why:** noise control is the point; a persistently broken viewer warning once beats warning
once per wave. Pull is always available and the warn says so.
**Impact:** T5/T12 pin the behavior.

## 2026-07-03 rid is pane-viewer-push, not the brief's oh-fu-01-viewer

**Context:** the dispatch brief said to record gates under `rid=oh-fu-01-viewer`.
**Decision:** gates are recorded under `pane-viewer-push`, the SPEC-070 canonical rid (branch
slug), with an `action` alias line left under `oh-fu-01-viewer` pointing here.
**Why:** `hooks/ship-gate.sh` keys its lane-completeness check on the BRANCH slug; recording
under any other rid would leave the enforced ledger empty and hard-block the push.
**Impact:** the run is auditable under both keys; enforcement sees the canonical one.
