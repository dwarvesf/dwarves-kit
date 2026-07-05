# Proof of done: ledger-observatory feature `docs-wiring` (SG-05, final)

> Per-feature record. The canonical multi-feature index is
> [`../proof-of-done.md`](../proof-of-done.md); this file is its `docs-wiring` feature detail.

| | |
|---|---|
| **Profile** | doc + wiring-check (no product behavior change) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Work-type dialect** | docs + one self-contained bash test file |
| **Spec** | [`../specs/SPEC-130-docs-wiring.md`](../specs/SPEC-130-docs-wiring.md) |
| **Canonical** | the tool index [`../proof-of-done.md`](../proof-of-done.md) (this is the `docs-wiring` feature detail) |

## 1. Acceptance criteria

| # | Criterion (measurable) | Status | Evidence |
|---|---|---|---|
| AC1 | README + proof-of-done + tool.toml + a MANIFEST.md row all present and current | PASS | R1 |
| AC2 | no-orphan: the render skill's frontmatter carries its 6 checked trigger phrases | PASS | R1 |
| AC3 | no-orphan: every `ledger <verb>` claimed by `uv run ledger <verb>` in skill/SKILL.md AND README.md matches a real `@app.command()` in `cli.py` | PASS | R1 |
| AC4 | no-orphan: `ledger anomalies --propose` (via `anomalies.stage_proposals`) actually stages a `## [staged]` block into a fixture cc-backlog buffer, end to end | PASS | R1 |
| AC5 | OVER-CLAIM negative control: a fabricated `ledger zzz-nonexistent` claim injected into a TEMP README copy is CAUGHT | PASS | R1, R2 |
| AC6 | the NC is load-bearing, not vacuous: deliberately neutering the claim-check turns the NC RED | PASS | R2 (deliberate break) |
| AC7 | the NC never mutates the real `README.md` (sha256 asserted unchanged) | PASS | R1 |
| AC8 | honesty fixes: `skill/SKILL.md` no longer claims the feedback loop unbuilt or the debt signal is "closest available"; `README.md` status table shows 04 merged / 05 in-progress | PASS | R3 |
| AC9 | the 4 known tradeoffs are stated in prose in README.md + proof-of-done.md, with the `repo="?"` figure backed by a live measurement, not an assumed number | PASS | R4 |
| AC10 | no `verification/{schema,etl-cli,render-skill,feedback-loop}` file for 01-04 was modified by this sub-goal | PASS | R5 |
| AC11 | full regression: all 5 test suites (schema, etl-cli, render-skill, feedback-loop, docs-wiring) green together | PASS | R6 |

## 2. Implementation

| Aspect | Detail |
|---|---|
| What | A doc-correctness pass over an already-shipped tool (README front door, SKILL.md honesty fixes, proof-of-done index finalization, tool.toml/MANIFEST/INVENTORY rows) plus one new self-contained no-orphan wiring test |
| Where | `tools/ledger-observatory/{README.md,skill/SKILL.md,tool.toml,docs/proof-of-done.md,tests/test-docs-wiring.sh}`; `../../MANIFEST.md`, `../../_meta/INVENTORY.md` |
| How it runs | `bash tools/ledger-observatory/tests/test-docs-wiring.sh`; no daemon, no new runtime dependency beyond `uv run python3` (already a tool dependency) |
| Claim-check mechanism | `unwired_claims()` extracts every `uv run ledger <verb>` invocation from a doc file and diffs it against the real `@app.command()` set parsed from `cli.py`; the OVER-CLAIM NC runs the identical function against a TEMP copy of README.md with one fabricated invocation appended |
| Touches | Doc-only + one new test file; no `src/` code touched, no `verification/*` per-feature file for 01-04 touched |

## 3. Confirmation run table

| # | Command | Result |
|---|---|---|
| R1 | `bash tools/ledger-observatory/tests/test-docs-wiring.sh` | 19/19 PASS, exit 0 (2026-07-03T21:22:57Z) |
| R2 | deliberate break: `unwired_claims()` patched to `echo ""; return 0` (always-clean, simulating a vacuous check), suite re-run | RED-as-expected: PASS=18 FAIL=1, the OVER-CLAIM line fails with `"check is vacuous"`; restored -> 19/19 |
| R3 | `grep -n "not built yet\|future sub-goal\|04-feedback-loop" skill/SKILL.md README.md` | no matches (clean) |
| R4 | `uv run ledger query "SELECT count(*) AS total, count(*) FILTER (WHERE repo = '?') AS unattributed FROM kit_runs" --json` against the live local lens | `{"total": 79, "unattributed": 35}` -> 44.3%, rounds to the "~44%" figure used in README/SKILL.md/proof-of-done.md |
| R5 | `git diff --stat -- tools/ledger-observatory/docs/verification/schema.md tools/ledger-observatory/docs/verification/etl-cli.md tools/ledger-observatory/docs/verification/render-skill/ tools/ledger-observatory/docs/verification/feedback-loop/` (vs. `main`) | empty diff |
| R6 | `bash tests/test-schema-conform.sh && bash tests/test-ledger-cli.sh && bash tests/test-render-skill.sh && bash tests/test-feedback.sh && bash tests/test-docs-wiring.sh` | 11/11, 26/26, 30/30, 39/39, 19/19 = 125/125, all exit 0 |

## 4. COVERAGE-DELTA

**Covered:** doc-presence, skill-fires (frontmatter trigger phrases), CLI-invoked (every claimed
verb resolves to a real command), work-intake-fed (a real `stage_proposals` call lands a block in
the fixture staging buffer), the over-claim NC (caught + load-bearing + file-safe), the 4 honesty
fixes (grep-clean), the 4 known tradeoffs stated with a live-measured number where applicable, no
accidental mutation of 01-04's proofs, full-suite regression.

**Not covered (explicitly, not hidden):** the no-orphan check is syntactic (regex/grep over doc
text vs. source), not semantic, it cannot detect a claim that is technically true but misleading
in framing, nor can it verify the render skill is actually SYMLINKED into any given host's
`~/.claude/skills/` (that installation step is outside ops-toolkit's repo scope by design, per the
SG-03 scope edge carried into this PR). The claim-check only recognizes the `uv run ledger <verb>`
invocation shape; a claim phrased differently (e.g. bare `` `ledger show` `` prose with no `uv run`
prefix) would not be swept, a known blind spot rather than a false confidence.
