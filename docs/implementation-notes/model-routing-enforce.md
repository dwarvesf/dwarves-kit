# Implementation notes , model-routing enforcement

Delta from `docs/specs/SPEC-116-model-routing-enforce.md` (orchestrate-hardening sub-goal 01).

## 2026-07-03 , the enforcement mechanism already existed (SPEC-087); this sub-goal is proof + pin

Read `lib/orchestrate.sh` before writing anything: `_route()` (SPEC-087, :392-403) already reads a
goal file's `Model:`/`Effort:` lines and both delegate dispatch sites (`cmd_run` serial :1159-1162,
`_wave_run` concurrent :784-788) already build `route_flags` and thread it through the single shared
`_run_one_session()` into the real `"$CLAUDE_CMD" -p $route_flags ...` call, across all three of its
mutually-exclusive run-paths (watchdog / stream-json / plain). There was no gap to build. The sub-goal
file (written before this session read the code) assumed the field was "documented but not provably
threaded" , that assumption was wrong; the wiring is real and was already partially proven by
`tests/test-orchestrate.sh` TEST 8 (sonnet tier + inherit negative control only).

## 2026-07-03 , route-suggest.sh cannot contradict Model: by construction, not by new code

`lib/route-suggest.sh` is a decompose-time SUGGESTER invoked by a human/`agents/meta-agent.md` Mode B
when DRAFTING a goal file, never by `lib/orchestrate.sh` at dispatch time (`grep -rn route-suggest
lib/orchestrate.sh` , zero hits). The "alignment check" the sub-goal asked for is therefore a
STRUCTURAL grep negative control (no call site in the dispatch functions), not a runtime mock , there
is no runtime interaction between the two scripts to mock.

## 2026-07-03 , fallback tier is "inherit", already decided by SPEC-107, not reopened here

SPEC-107 ("cheap-tier defaults") already resolved the write-time vs read-time distinction: authoring
surfaces now write `Model: sonnet` by default instead of omitting the field, but `_route()`'s
absent-field behavior (empty `route_flags` -> the child `claude -p` inherits the parent tier) was
explicitly left UNCHANGED (SPEC-107 "Open questions"). This spec's negative control proves that
read-time fallback is real (no crash, no silently-wrong tier), it does not re-decide what the fallback
should be.

## 2026-07-03 , test scope: full tier matrix on serial, one case on wave (not a full matrix)

`tests/test-model-routing.sh` extends the serial-path mock pattern from `tests/test-orchestrate.sh`
(cheap: no git-init, no worktree) to prove opus/sonnet/haiku all thread correctly, plus the no-`Model:`
negative control. For the wave (concurrent) path it proves exactly ONE tier (opus) end-to-end via the
heavier throwaway-git-init mock pattern from `tests/test-orchestrate-wavefront.sh` , the wave dispatch
site is byte-identical in structure to the already-proven serial site (same `_route()` call, same
`route_flags` construction), so a full second tier matrix on the wave path would be redundant proof at
disproportionate cost (git-init + worktree spin-up per case). If `_wave_run`'s routing logic ever
diverges from `_route()`'s shared contract, this one case still catches it.

## 2026-07-03 , independent code-review pass (kit:code-reviewer, test-coverage lens)

Mutation-tested the new suite before shipping: neutralized the `--model` flag build on the serial
line and, separately, on the wave line in a scratch copy of `lib/orchestrate.sh`, and confirmed the
matching test cases correctly flip to FAIL each time (rules out a rubber-stamp test that would pass
even if the wiring broke). Two advisory, non-blocking gaps the reviewer flagged, filed here rather
than fixed, since they are pre-existing or explicitly out of this spec's scope: (1) `_route()`'s own
parse edge cases (case-insensitive match, trailing whitespace, multiple `Model:` lines, malformed
lines) have no dedicated test anywhere in the repo , cheap to add later, not introduced by this spec;
(2) the wave path's sonnet/haiku tiers are untested (opus only, by design , see the note above).
`tests/test-routing.sh` (route-suggest.sh's own suite, untouched by this diff) fails on this host
under the stock `/bin/bash` 3.2 (needs bash 4+ for `mapfile`/assoc arrays); pre-existing environment
gap, confirmed green under homebrew bash 5.3, not caused by or in scope for this change.
