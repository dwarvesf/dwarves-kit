# Implementation notes: SPEC-195 (learn propose, harness-loop SG-05)

Delta from SPEC-195 / the goal contract only; not a restatement.

## 2026-07-12 Language: Python stdlib for propose.py + staging_format.py (not bash)

Context: `lib/learn/learn.sh` is bash and forwards `debt` to `weekend-batch.sh` (bash).
Decision: `propose` forwards to `python3 propose.py`. Why: every surface propose integrates
with is Python (`stats` is a uv CLI emitting JSON; the two existing staged-block writers
`hooks/backlog-stage.py` + `anomalies.py` are Python; the reader `add-backlog` is Python). A
bash implementation would reimplement JSON parsing + the byte-format writer in a second
language and drift from the readers. Stdlib only (no uv needed for propose itself; it shells
out to `bin/stats` which owns the uv boundary). Impact: `learn.sh` gains one `python3` exec arm.

## 2026-07-12 Shared staging-format helper landed here (SG-05 merged first)

Per the shared-fixture rule, checked the branch: SG-06 (`learn drain`) had not merged a
`lib/learn/staging-format*` helper. So SG-05 lands `lib/learn/staging_format.py` as the ONE
definition of the block edges (`render_block`, `parse_blocks`, `norm`, `existing_keys`).
Filename uses an underscore (`staging_format.py`, not `staging-format.py`) so it is importable
as a Python module by both propose.py and SG-06's drain; the goal's `staging-format*` glob is
descriptive intent, and the module is clearly within the `lib/learn/` fence. It also runs as a
thin CLI (`parse`/`render`) so a non-Python consumer could shell out to it. Block edges match
`add-backlog.parse_staging` exactly (next-`## [`-header delimited; single-alpha field keys).

## 2026-07-12 Anti-fabrication: citation is REBUILT from the aggregate, never from the model

The spec's cite-the-number discipline is enforced STRUCTURALLY, not by trusting the model. The
interpret pass returns only a `signal` id per hypothesis; the staged block's `- Source:` line
(lens + figure + rids) is looked up from `aggregate[signal]` by id and rebuilt deterministically
in `_citation_source()`. A model that hallucinates a figure cannot inject it, because the figure
is never read from the model's prose. This is what makes "an ungrounded proposal reaching
staging = P0" a closed hole rather than an LLM-judgment gamble.

## 2026-07-12 Stage-3 order: grounding -> dedup -> adversarial (spec-validate finding MAJOR-4)

Dedup (deterministic, cheap) runs BEFORE the per-hypothesis adversarial `claude -p` pass, so an
exact-duplicate proposal never burns a model call. Grounding is first (also cheap). Only
grounded, non-duplicate survivors reach the LLM verifier. Keeps the weekly cycle's spend minimal
and observable, aligning with the "dedup HARD is the cheap anchor" framing.

## 2026-07-12 Grounding drops present-but-empty-figure signals (spec-validate finding CRITICAL-2)

`build_aggregate.add()` already skips a signal whose figure is empty, so an empty-figure signal
never enters the aggregate. Belt-and-suspenders: the grounding check also drops a hypothesis
citing a signal whose `figure` is falsy (`if signal is None or not signal.get("figure")`). Both
guards, so a "structurally grounded but evidentially empty" proposal cannot reach staging. Own
test row added.

## 2026-07-12 Rid fallback so TOKENS never goes dark on master/detached (finding CRITICAL-1)

`gate-ledger.sh rid` exits 1 empty on master/detached HEAD, and `gate-ledger.sh tokens` refuses
an empty rid. `_rid()` resolves `LEARN_PROPOSE_RID` -> `gate rid` (only when it exits 0 with
non-empty output) -> a branch-independent `learn-propose-<date>` slug. So the interpret +
adversarial TOKENS markers always land, including under the weekly cadence (which runs before
any goal branch exists). Tested by breaking the gate path and asserting the date-slug fallback.

## 2026-07-12 Figure sanitization keeps the Source citation on one line (finding MAJOR-5)

`memory-sweep` and other surfaced figures are free-ish text. `_citation_source()` strips
`|`, `\n`, `\r` to a space before interpolating `figure` into the single-line `- Source:` field,
so a multi-line lens figure can never split the block or silently truncate the `rids=` tail
under `add-backlog`'s `(.+)$` field regex. Tested with an injected multi-line figure.

## 2026-07-12 Config flip: auto_improvement stays in the no-live-path guard (finding MAJOR-3)

Rather than removing `auto_improvement` from `RESERVED_FEATURES_KEYS`, it STAYS there and only
the status-tag assertion flips `[design]` -> `[impl]`. The no-live-path guard now enforces a
LIVE invariant: an `[impl]` flag that must never be read kit-side (the command is always
available; the weekly cadence gates on the flag CONSUMER-side, SG-10). This keeps CI protection
against a future accidental kit-side wire-up, which the design says must never happen. No
kit-side `kit_config_get features.auto_improvement` read is added by this SG.

## 2026-07-12 Window is best-effort (kit_gates start_ts is sparse)

`kit_gates` carries `(rid, gate, outcome, caught, reason, start_ts, end_ts)` with start_ts/
end_ts NULL on the real corpus (no OUTCOME emitter yet). So a strict `--days` timestamp filter
is not reliable. `--megas N` trims to the last N rids deterministically; `--days` bounds the
per-lens `--window-days` where the lens supports it, and the cited rids are the window's covered
rids (best available). This matches the research doc's "windowing is per-lens" and is documented
in propose.py `_window_rids`.

## 2026-07-12 Fence touches outside the literal globs (noted, within spirit)

- `lib/learn/learn.sh` (the `propose)` dispatch arm) is outside `propose*` but IS the propose
  verb's wiring -- within the fence's spirit.
- The goal's `tests/test-config-reserved-keys*` glob names the real file
  `tests/test-reserved-config-guard.sh` (SPEC-188's actual test). Edited the real file.
- `tests/test-bin-forwarders.sh` (SG-04's census): the two propose stub rows only, per the
  coordinator's CI-fix directive (see next entry).

## 2026-07-12 CI red: SG-04's stub NC in test-bin-forwarders.sh invalidated by the implementation

Context: PR #243's first CI run failed on both OSes in `tests/test-bin-forwarders.sh`:
"learn propose exits 1" and "learn propose names SPEC-195" -- SG-04's REFUSE-stub NC, which
this SG's implementation of the verb correctly invalidates. Root cause of the local-vs-CI
mismatch: the local verification ran only the four suites named in SPEC-195's Verification
section; CI runs the full `tests/` step list, which includes SG-04's forwarder census.

Decision: replaced ONLY the two propose rows with an engine-reach check, same class as the
`learn debt mark-paid reaches the engine` row in the same file: `bin/learn propose --help`
must exit 0 and print the engine's own argparse usage naming "cross-run backlog proposer
(SPEC-195)". `--help` is the deterministic no-env probe -- a bare `learn propose` run would
invoke the live stats/LLM pipeline, which CI must never do. The drain stub rows (SPEC-196)
are untouched: the SG-06 sibling makes the same class of edit for `drain` on its branch, so
this edit stays line-disjoint (the shared section-header comment is left stale for the same
reason; whichever merges second reconciles it).

Impact: `tests/test-bin-forwarders.sh` 30/30 locally; full CI list (48 suites) re-run green
locally before push. Lesson for later SGs: "full suite" = the CI step list, not the spec's
Verification block.
