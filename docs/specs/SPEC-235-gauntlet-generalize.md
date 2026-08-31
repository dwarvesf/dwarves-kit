# Spec: Generalize /kit:gauntlet into a parameterized probe-convergence engine
Generated: 2026-08-31
Status: DRAFT
References: `commands/gauntlet.md` (the engine mechanics to preserve verbatim: two-tier loop, severity grammar, run-record contract, rules 1-10); `commands/test-plan-review-team.md` (the bounded-revise sibling whose marker grammar gauntlet shares); `tests/gauntlet/` (the onboarding instance that becomes the reference preset, imitate its slot shapes, never rewrite it).

## Problem

The gauntlet is the kit's only workflow where a FIXED OUTCOME drives discovery: fresh clean-room probe agents attempt an outcome contract, and the artifact they consumed gets revised when they fail. That shape is the dual of `/goal` (one persistent agent mutates the work toward a fixed verifier; the gauntlet mutates the artifact toward a fixed outcome using disposable probes, because a persistent agent learns to compensate for a bad artifact and hides the defect).

Today `commands/gauntlet.md` welds that engine to one instance: onboarding. The vocabulary ("contributor surface", "seed card", "new contributor"), the input defaults (CONTRIBUTING.md globs), and the guide docs all assume the artifact is contributor docs. An operator who wants the same engine for a runbook rebuild-from-zero test, an experiment protocol reproducibility check, a spec completeness probe, or API DX cannot invoke it without mentally translating every input. The engine is general; the command is not.

## Solution

### Approaches considered

1. **Parameter seam + presets in the existing command** (chosen). Rewrite `commands/gauntlet.md` around named slots (artifact, outcome contract, probe framing, clean-room recipe); onboarding becomes the shipped reference preset carrying today's exact defaults. Tradeoff: one longer command file, but zero new files to keep in sync and zero consumer breakage.
2. **New `/kit:converge` engine command + `/kit:gauntlet` as a thin onboarding wrapper.** Cleanest naming, but splits one contract across two prompt files that will drift, breaks the SPEC-226 phase-name literal `gauntlet`, and forces every projection (FEATURES, README, workflow-map) to gain a row. Rejected: cost is real, benefit is naming only.
3. **Per-preset command files** (`/kit:gauntlet-onboarding`, `/kit:gauntlet-runbook`, ...). Rejected: N copies of the probe-safety invariants is exactly the drift the pitfalls research warns about (invariants live in only two files today; multiplying them is how they rot).

### Chosen approach + why

Approach 1. The engine mechanics are already generic (loop, run-record, rules, telemetry); the change is a vocabulary seam plus a preset table. Everything that exists keeps working: the onboarding preset's defaults are byte-compatible with today's inputs, so `tests/gauntlet/**` and the campaign deploy plist stay valid without edits.

### Extensibility & boundaries

- Load-bearing dimension: number of presets. Adding one = adding a row to the command's preset table plus (optionally) a worked example in the guide. No script, config, or telemetry change; the engine slots are the interface.
- Unit boundaries: the ENGINE (loop, rules, telemetry, run-record) owns invariants; a PRESET owns only slot values (artifact globs, outcome contract, probe framing, clean-room recipe). A preset can never override an engine rule; the command states this precedence explicitly.

### Architecture

See `## Design`.

## Picture

```
            ENGINE (invariant)                      PRESET (per instance)
 ┌─────────────────────────────────────┐   ┌────────────────────────────────────┐
 │ bounded-revise loop (cap, converge) │   │ slot 1: ARTIFACT under convergence │
 │ two-tier cost routing (T1 -> probe) │   │         (globs the reviser edits)  │
 │ severity grammar BLOCKER/MAJOR/MINOR│◀──│ slot 2: OUTCOME CONTRACT           │
 │ run-record contract (ROUNDS.md ...) │   │         (probe card + checker +    │
 │ rules 1-10 (probe never coached,    │   │          Tier-1 command)           │
 │  fresh room, scrub, replicate, ...) │   │ slot 3: PROBE FRAMING              │
 │ telemetry rails (SPEC-226, QL-VERDICT│  │         (persona + model tier)     │
 │  grammar preset-invariant)          │   │ slot 4: CLEAN-ROOM RECIPE          │
 └─────────────────────────────────────┘   │         (per artifact kind)        │
                  ▲                        └────────────────────────────────────┘
                  │ consumes slots                     ▲
        ┌─────────┴──────────┐                         │ shipped reference
        │ /kit:gauntlet run  │              ┌──────────┴─────────┐
        │ round N: T1 -> probe│             │ preset: onboarding │
        │ -> score -> revise  │             │ (today's defaults, │
        │ artifact -> respin  │             │  tests/gauntlet/**)│
        └────────────────────┘              └────────────────────┘
```

## Design

**Ordering:** the slot interface hardens first (presets depend on it), doc restructure second, projection wording last.

### Approaches considered + chosen

Per `## Solution`. The design-bearing decision is the slot interface and its precedence rule.

### Diagram

```
 operator ──▶ /kit:gauntlet <preset|custom slots>
                  │ resolve slots (preset row ∪ overrides; validate per bad-input table)
                  ▼
            round N ──▶ Tier 1 (slot 2's deterministic command)
                  │  red? findings, skip probe
                  ▼  green
            clean room (slot 4 recipe) + probe (slot 3 framing) + card (slot 2)
                  │
                  ▼
            score vs checker (slot 2) ──▶ K=0 ──▶ replicate ──▶ SOLID
                  │ K>0
                  ▼
            reviser edits ONLY slot 1 globs ──▶ commit ──▶ teardown ──▶ round N+1
            (severity must fall; cap 3; else REVISE / RECONSIDER)
```

### ADR link(s)

No ADR: the decision is reversible (the command file is the whole surface; approach 2 remains available later if presets multiply). The `/goal`-duality positioning lands in `docs/patterns/gauntlet.md`, which already serves as the design record for gauntlet.

### Boundaries & failure modes

Out of bounds: `tests/gauntlet/**` content, `kit.toml` key shapes, SPEC-226's phase name and marker grammar, any lib/hook script. See `## Failure modes`.

## Technical Design

### Interfaces (I/O contract)

- Inputs / consumes: the four slots, replacing the onboarding-worded rows of today's Inputs table.
  - **Artifact under convergence** (was "Surface globs"): the globs the reviser may touch. The thing that evolves.
  - **Outcome contract** (was "Seed card" + "Submission checker" + "Tier 1 command"): a probe task card (goal contract: outcome + AC + verification command + termination-on-blocker), a deterministic checker (any oracle over the probe's output, not necessarily a patch), and the Tier-1 deterministic suite.
  - **Probe framing** (was the hardcoded "new contributor" instruction): the persona line handed to the probe, plus the probe model tier (mid-tier default and its rationale stay engine-level).
  - **Clean-room recipe** (generalized): how a fresh environment is built from committed/versioned state, BY ARTIFACT KIND: repo artifact = `git archive HEAD` + container (today's recipe); host/service artifact = a declared snapshot/restore recipe; doc-only artifact = minimal container holding only the artifact + the card. The recipe must state its own answer-key exclusion (rule 7) and its own "clean room vs real target" gap (patterns limit 8).
  - Unchanged inputs: Target repo, Probe credentials, Round cap, Runner host (`kit.toml [gauntlet] runner_host` / `probe_key_ref`, one shared pair for all presets, root-only-readable, key shape frozen).
- Outputs / produces: unchanged. Run-record contract (`docs/verification/gauntlet/<date>-<slug>/`, ROUNDS.md grammar), `[[QL-VERDICT round=N clean=<bool> findings=K]]` marker byte-identical across presets, gate-ledger phase literal `gauntlet`. ROUNDS.md's inputs table gains one `preset:` row (free text; `custom` when slots are hand-assembled), which is where dashboards distinguish presets, never the phase name.
- Invariants: engine rules 1-10 bind every preset; a preset supplies slot VALUES only and can never weaken a rule. Probe-safety invariants (spend-capped key only, no answer key, scrub transcripts, mid-tier probe) are stated once, engine-level.

### Data model changes

None.

### API changes

`/kit:gauntlet` invocation gains an optional preset argument; bare invocation with the old onboarding inputs still resolves (the onboarding preset's defaults ARE those inputs).

### UI changes

None.

### Infrastructure changes

None. `tests/gauntlet/deploy/mini.gauntlet-campaign.plist` keeps working because the onboarding preset preserves today's input names and defaults (compat-checked in TASK-004).

## Task Breakdown

### Phase 1: Engine seam

- [ ] TASK-001: Rewrite `commands/gauntlet.md` around the four slots. Frontmatter description reworded to engine-generic ("probe-convergence engine... onboarding ships as the reference preset"). Body: engine sections (loop, run-record, rules, telemetry) keep their exact mechanics; Inputs table becomes the slot table + unchanged rows; a `## Presets` section defines `onboarding` (today's defaults verbatim, pointing at `tests/gauntlet/` and foundation-workers SPEC-018 as worked instances) and names candidate future presets in one line each (runbook rebuild-from-zero, experiment-protocol reproducibility, spec completeness, API DX) WITHOUT specifying them; bad-input teach-then-fix table genericized (rows keep their onboarding examples as examples); the `/goal`-duality paragraph added to the positioning intro. Acceptance: every rule 1-10 present with meaning unchanged; QL-VERDICT and ROUNDS.md grammar unchanged except the added `preset:` row; onboarding preset defaults match today's table byte-for-byte where they were concrete.

### Phase 2: Companion docs

- [ ] TASK-002: Genericize `docs/patterns/gauntlet.md` wording ("contributor surface" -> "artifact under convergence"); restate limits 4 and 8 per artifact kind (host-based clean rooms have a larger answer-key surface and a larger clean-room-vs-real-target gap); add the `/goal`-duality positioning. Restructure `docs/guides/gauntlet.md`: generic checklist top layer, onboarding kept as the worked example. Update `lib/config/module-registry.md:52` wording (engine + preset framing; key names untouched). Acceptance: `grep -i "contributor surface" docs/patterns/gauntlet.md` returns only historical/lineage mentions; both config docs still state `gauntlet.runner_host` / `gauntlet.probe_key_ref` literally.

### Phase 3: Projections

- [ ] TASK-003: Regenerate `docs/FEATURES.md` (`bash lib/registry/feature-registry.sh generate`); hand-update `README.md` (module list row + command table row) and `docs/workflow-map.md` gauntlet rows to engine-generic wording; add the missing `/kit:gauntlet` line to `docs/workflow-paths.md` section 5 (pre-existing drift found by research, fix while touching the area). Acceptance: FEATURES.md freshness gate green; workflow-paths has exactly one gauntlet command line.

### Phase 4: Verification

- [ ] TASK-004: Compat pass. Run the kit suite; grep-verify the onboarding preset's input names/defaults against `tests/gauntlet/cleanroom/run.sh` and `tests/gauntlet/README.md` expectations; confirm `tests/gauntlet/deploy/` scripts reference nothing renamed. Acceptance: suite green; a written note in the run record (implementation-notes) listing each consumer checked.

## After state

- [ ] `commands/gauntlet.md` defines the engine via four named slots and a `## Presets` section; onboarding is a preset row, not the command's identity. (Today: onboarding vocabulary is welded through the whole file.) Checkable: `grep -c "artifact under convergence" commands/gauntlet.md` >= 1 and the frontmatter description no longer begins "Onboarding gauntlet".
- [ ] An operator can hand the command a non-onboarding (artifact, outcome contract) pair and the bad-input table validates it without any onboarding assumption. (Today: inputs table literally asks for CONTRIBUTING.md globs.)
- [ ] `docs/FEATURES.md` regenerated; `docs/workflow-paths.md` carries a gauntlet line. (Today: FEATURES row says "Onboarding gauntlet"; workflow-paths has zero gauntlet lines.) Checkable: `grep -c gauntlet docs/workflow-paths.md` >= 1.
- [ ] `tests/gauntlet/**`, `kit.toml`, SPEC-226 contract: zero edits. Checkable: `git diff --stat master -- tests/gauntlet kit.toml docs/specs/SPEC-226-gauntlet-telemetry-learning.md` empty.

## Acceptance Criteria (global)

- [ ] All tasks pass their individual acceptance criteria
- [ ] Kit suite green (`bash tests/test-meta.sh` and the FEATURES freshness gate)
- [ ] No regressions: onboarding preset is byte-compatible with today's documented inputs; no consumer (tests, deploy plist, config docs) references anything renamed

## Verification

```
cd <worktree>
bash tests/test-meta.sh
bash lib/registry/feature-registry.sh generate && git diff --exit-code docs/FEATURES.md
git diff --stat master -- tests/gauntlet kit.toml   # must be empty
grep -c gauntlet docs/workflow-paths.md              # >= 1
```

## Edge Cases

1. Operator invokes `/kit:gauntlet` bare in a repo with onboarding fixtures present: resolves to the onboarding preset, behavior identical to today.
2. Operator supplies custom slots that omit a checker: bad-input table fires ("derive one from the card's verification command"), generic wording, same as today.
3. A preset proposes editing files outside its artifact globs (e.g. a spec-completeness preset tempted to fix product code): rule 4 (artifact-only revisions) blocks it; finding recorded instead.
4. Host-kind clean-room recipe declared but no snapshot/restore procedure named: treated as "no clean-room recipe" in the bad-input table (a host you cannot rebuild is not a clean room).
5. Two presets run in the same repo on the same day: run-record dirs collide only if slugs match; the slug rule (date + slug) already disambiguates; ROUNDS.md `preset:` row records which ran.
6. QL-VERDICT parsing: a preset run emits the identical marker grammar; observe/stats need no change (SPEC-226 claim preserved).

## Failure modes

| Failure class | Detection signal | Mitigation / recovery |
|---|---|---|
| Onboarding consumer breaks (tests/gauntlet, campaign plist) | TASK-004 grep + suite red | onboarding preset pins today's names/defaults; revert is one file |
| Config-doc desync (kit-config.sh vs module-registry.md) | manual cross-check in TASK-002 acceptance | both updated in one commit; key shape frozen by spec |
| Marker/grammar drift across presets | none today (untested) | spec pins grammar preset-invariant; ROUNDS.md carries preset identity |
| Projection drift (FEATURES/workflow-paths) | test-meta freshness gate; topology-drift audit | regenerate + add the missing baseline line in this PR |

## Out of Scope

- Rewriting `tests/gauntlet/**` (it IS the onboarding preset's implementation; generalizing the cleanroom stager is future work if a second preset materializes).
- Building any second preset (runbook, experiment, spec-completeness, API DX are named as candidates only).
- Per-preset `kit.toml` config (one shared runner_host/probe_key_ref pair stands until a preset demonstrably needs its own).
- Scenario-pack/campaign machinery (SPEC-227) stays onboarding-preset-only.
- `lib`/`hooks` script changes; SPEC-226 contract changes.

## Decision Log

- DEC-001: Generalize in place with presets, not a new engine command. Rationale: preserves the SPEC-226 phase literal, every projection row, and all consumers; naming purity was the only benefit of splitting. Rejected: `/kit:converge` split, per-preset command files.
- DEC-002: Preset identity travels in ROUNDS.md (`preset:` row), never in the gate-ledger phase name or the QL-VERDICT marker. Rationale: pitfalls 8/9, phase renames touch `normalize_phase` and stats grouping; the run record is the eval artifact and the right home.
- DEC-003: One shared `[gauntlet]` config pair for all presets, key shape frozen. Rationale: pitfall 1-3, `runner_host` is security-bearing and root-only-readable; nesting keys breaks the selftest and the registry doc for zero present need.
- DEC-004: Probe-safety invariants stay engine-level, stated once. Rationale: pitfall 4, they exist in exactly two files today; per-preset restatement is the drift vector.

## Open questions

(none; a /goal loop appends here if it hits a decision this spec does not cover, then stops)
