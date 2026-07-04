# Verification: SPEC-145 advisor-visibility

Real dispatches and real commands, not a hand-simulated transcript. The fixture ledger logs
are committed at `tests/fixtures/advisor-ledger-emit/runs/` and are reproducible verbatim.

## What "done" means here

Two negative controls, both required by the goal file:
- **NC1 (honest-zero):** a rid with no advisor dispatch renders zero/absent in `kit_gates`.
- **NC2 (emit-failure-never-blocks):** the emit command failing never fails the surrounding
  review/dispatch; a visible warning prints instead.

Plus one proof-of-parse: the new `advisor` gate name needs ZERO code change in the merged
`ledger-observatory` (`tools/ledger-observatory/`, ops-toolkit, sibling repo, PR #672-#683,
already shipped) `kit_gates` reader/`gate-yield` CLI, because `read_kit_gates()` treats every
`| GATE | <phase> | <outcome> | <reason> |` line generically by phase name.

## Fixture

```
tests/fixtures/advisor-ledger-emit/runs/
├── advisor-visibility-fixture.log   # a rid that dispatched advisor (both P5 and P6)
└── no-advisor-fixture.log           # a rid that ran, but never dispatched advisor
```

`advisor-visibility-fixture.log`:
```
2026-07-04T10:00:00Z | START | lane=full classified=full type=spec-feature ctype=spec-feature repo=dwarves-kit
2026-07-04T10:00:01Z | GATE | spec | ran | SPEC-145-advisor-visibility approved, tasks=8
2026-07-04T10:00:02Z | GATE | review | ran | SHIP findings=1 suppressed=0 rejected=0 actor=Test Actor
2026-07-04T10:00:03Z | GATE | advisor | ran | mode=P5 findings=2 actor=Test Actor
2026-07-04T10:00:04Z | GATE | advisor | ran | mode=P6 findings=3 actor=Test Actor
```

`no-advisor-fixture.log`:
```
2026-07-04T09:00:00Z | START | lane=tiny classified=tiny type=spec-feature ctype=spec-feature repo=dwarves-kit
2026-07-04T09:00:01Z | GATE | build | ran | one-line fix, no advisor dispatch on this rid
2026-07-04T09:00:02Z | GATE | review | ran | SHIP findings=0 suppressed=0 rejected=0 actor=Test Actor
```

## Run 1: `kit_gates` parses the new `advisor` phase with zero ledger-observatory code change

```bash
cd tools/ledger-observatory   # ops-toolkit, sibling repo, PR #672-#683 already merged, unmodified
export DWARVES_KIT_LOG_DIR="<path>/tests/fixtures/advisor-ledger-emit"   # points at the committed fixture above
export LEDGER_OBSERVATORY_DB="<scratch>/lens.duckdb"
uv run ledger rebuild
uv run ledger gate-yield --table
uv run ledger query "SELECT rid, gate, outcome, reason FROM kit_gates WHERE gate='advisor' ORDER BY rid, reason" --table
```

Result (verbatim):
```
{
  "kit_runs": 2,
  "kit_gates": 6,
  ...
}

+---------+-----+----------+---------+--------+-------+--------------+
| gate    | ran | override | skipped | caught | total | override_pct |
+---------+-----+----------+---------+--------+-------+--------------+
| advisor | 2   | 0        | 0       | 0      | 2     | 0.0          |
| build   | 1   | 0        | 0       | 0      | 1     | 0.0          |
| review  | 2   | 0        | 0       | 0      | 2     | 0.0          |
| spec    | 1   | 0        | 0       | 0      | 1     | 0.0          |
+---------+-----+----------+---------+--------+-------+--------------+
(4 rows)

+----------------------------+---------+---------+-------------------------------------+
| rid                        | gate    | outcome | reason                              |
+----------------------------+---------+---------+-------------------------------------+
| advisor-visibility-fixture | advisor | ran     | mode=P5 findings=2 actor=Test Actor |
| advisor-visibility-fixture | advisor | ran     | mode=P6 findings=3 actor=Test Actor |
+----------------------------+---------+---------+-------------------------------------+
(2 rows)
```

**Outcome:** `advisor` appears as a first-class row in `gate-yield`'s per-gate aggregate
(2 ran, 0 caught -- expected, since no run ledger emits a real `| OUTCOME |` bracket yet,
per SPEC-131 DEC-003, unrelated to this change) and the per-row query returns both the
`mode=P5` and `mode=P6` rows verbatim, parsed by the UNMODIFIED reader.

## Run 2: NC1, honest-zero

```bash
uv run ledger query "SELECT rid, count(*) FILTER (WHERE gate='advisor') AS advisor_rows, count(*) AS total_rows FROM kit_gates WHERE rid='no-advisor-fixture' GROUP BY rid" --table
uv run ledger query "SELECT rid, gate, outcome FROM kit_gates WHERE rid='no-advisor-fixture' ORDER BY gate" --table
```

Result (verbatim):
```
+--------------------+--------------+------------+
| rid                | advisor_rows | total_rows |
+--------------------+--------------+------------+
| no-advisor-fixture | 0            | 2          |
+--------------------+--------------+------------+
(1 row)

+--------------------+--------+---------+
| rid                | gate   | outcome |
+--------------------+--------+---------+
| no-advisor-fixture | build  | ran     |
| no-advisor-fixture | review | ran     |
+--------------------+--------+---------+
(2 rows)
```

**Outcome: NC1 confirmed.** `no-advisor-fixture` genuinely ran (2 other gate rows: `build`,
`review`) but has **zero** `advisor` rows -- `kit_gates` reports the honest zero, it does not
fabricate coverage for a rid that never dispatched the advisor.

## Run 3: NC2, emit-failure-never-blocks

```bash
RO_DIR=<scratch>/advisor-nc2-readonly
mkdir -p "$RO_DIR/runs"; chmod 555 "$RO_DIR/runs" "$RO_DIR"
cd <dwarves-kit worktree>
export DWARVES_KIT_LOG_DIR="$RO_DIR"
rid="nc2-fixture"
# the emit line VERBATIM from commands/review-team.md's Step 2b:
bash lib/gate-ledger.sh record "$rid" advisor ran "mode=P5 findings=1 actor=Test Actor" \
  || echo "WARNING: advisor gate-ledger emit failed (ledger dir unwritable?); review output unaffected" >&2
echo "exit code of the compound command: $?"
echo "REVIEW OUTPUT: verdict=SHIP findings=1 (unaffected by the failed emit above)"
```

Result (verbatim):
```
lib/gate-ledger.sh: line 177: <RO_DIR>/runs/nc2-fixture.log: Permission denied
WARNING: advisor gate-ledger emit failed (ledger dir unwritable?); review output unaffected
exit code of the compound command: 0
REVIEW OUTPUT: verdict=SHIP findings=1 (unaffected by the failed emit above)
```

**Outcome: NC2 confirmed.** The `record()` call fails hard (`Permission denied`, a read-only
`runs/` directory) exactly as it would on a genuinely unwritable ledger. The `||` fallback
catches it, prints the warning, and the compound command's own exit status is `0` -- the
downstream review flow (the stand-in `REVIEW OUTPUT` line) runs unaffected. No propagated
failure, no swallowed warning.

## Multi-lens review (SPEC-069-shaped, dogfooding `/kit:review-team`)

Dispatched via `Agent` (the same subagent types `/kit:review-team` itself dispatches):
`kit:security-reviewer`, `kit:code-reviewer` (architecture lens), `kit:code-reviewer`
(test-coverage lens), `kit:advisor` (critique mode, P5). Each read the real diff
(`git diff master -- commands/review-team.md commands/mega.md agents/advisor.md
tests/test-advisor-ledger-emit.sh docs/specs/SPEC-145-advisor-visibility.md`) directly off
disk in this worktree.

**Security: SECURE, 0 findings.** `$rid`/`$(git config user.name)` sanitized upstream by
`runid()`; fail-open `||` cannot hide a security-gate failure (nothing gate-worthy depends on
this row); no secrets in the diff.

**Architecture: 9/10, 1 LOW (FIXED).** The advisor emit is the first `record()` call site with
an explicit `|| WARNING` fallback, unreconciled with ~15 bare sibling sites and no doc anchor.
Fixed: `WORKFLOW.md`'s "Gate ledger and ship enforcement" section now names this as
SPEC-145-specific (NC2), not a new ledger-wide default.

**Test-coverage: 6/10, 3 findings (1 HIGH, 1 MEDIUM, 1 LOW-MEDIUM), all FIXED.** HIGH
(reproduced live): `fail_open_call()`'s sticky global flags let a missing fallback on
`mega.md`'s SECOND (P6) call site slip past AC3, masked by the first (P5) match. Fixed:
per-match independent checking; reproduced the bug against a mutated copy first, confirmed the
rewrite catches it. MEDIUM: no test called the real `lib/gate-ledger.sh record` write path.
Fixed: new AC8 invokes it live and asserts the exact written line. LOW-MEDIUM: AC5 didn't pin
the rid-convention text in `agents/advisor.md` itself. Fixed. Suite: 23/23 -> 27/27.

**Advisor critique (P5): 2 findings, both FIXED.** (1) The convergence-gate paragraph named a
per-loop-iteration `$RID` variable not guaranteed to survive to convergence-gate time under
the default subagent/delegate run modes. Fixed: reworded to a STATIC value (the final
sub-goal's `**Branch:**` header, `type/` stripped), never a live re-derivation. (2)
"Mirrors... catching up" risked implying full parity with the skill's COMPOSED convergence
gate (verify + review-team + advisor); this sub-goal wires only the advisor third. Fixed:
reworded to "the ADVISOR SLICE" and added an honest Out-of-Scope bullet in the spec naming the
`/kit:verify`/`/kit:review-team` gap as pre-existing, unclosed by this pass. Previously
rejected: 0.

**Verdict: SHIP.** All 6 findings across 4 lenses fixed and re-verified. Recorded on this
sub-goal's own rid, dogfooding the very convention this spec built:
```
bash lib/gate-ledger.sh record advisor-visibility advisor ran "mode=P5 findings=2 actor=Han Ngo"
bash lib/gate-ledger.sh record advisor-visibility review ran "SHIP findings=6 suppressed=0 rejected=0 actor=Han Ngo"
```
`bash lib/gate-ledger.sh show advisor-visibility` now itself contains a real
`| GATE | advisor | ran | mode=P5 findings=2 actor=Han Ngo |` row -- a live, non-fixture
confirmation that this rid's own review pass produced exactly the row shape this spec exists
to make visible.

## Reproduce

```bash
# 1. cd tools/ledger-observatory (ops-toolkit); uv sync
# 2. export DWARVES_KIT_LOG_DIR=<dwarves-kit worktree>/tests/fixtures/advisor-ledger-emit
# 3. uv run ledger rebuild && uv run ledger gate-yield --table
# 4. uv run ledger query "SELECT rid, gate, outcome, reason FROM kit_gates WHERE gate='advisor'" --table
# 5. For NC2: chmod 555 a scratch runs/ dir, point DWARVES_KIT_LOG_DIR at it, run the emit
#    line from commands/review-team.md Step 2b verbatim.
```

## Verdict

PASS. Both NCs captured with real command output (not asserted); the new `advisor` phase
parses through the merged, unmodified `kit_gates` reader with zero ledger-observatory code
change. Offline regression coverage for the prose contract itself:
`bash tests/test-advisor-ledger-emit.sh` (27/27, post multi-lens review fixes -- see "Multi-lens
review" above), plus the full existing suite (`tests/test-advisor.sh` 15/15,
`tests/test-review-team-plants.sh` 8/8, `tests/test-command-emit-sweep.sh` 19/19,
`tests/test-mega-reconcile.sh` 35/35, `tests/test-meta.sh` 669/669, `tests/test-hooks.sh`
452/452) -- no regression, no gate-requirement change.
