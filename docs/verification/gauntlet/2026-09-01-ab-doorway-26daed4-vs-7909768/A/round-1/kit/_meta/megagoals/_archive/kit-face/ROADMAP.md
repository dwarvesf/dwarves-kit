# Mega-goal: kit-face

**Destination:** dwarves-kit presents production-ready and measures its own cost: a current README with a native-rendered lifecycle diagram, a navigable docs map, token-efficiency metrics riding the run ledger, cheap-tier defaults across all three tier surfaces, meta-agent provenance + a runtime efficacy metric, an operator-persona design lens with a recorded governance boundary, three UI done-modes including a bounded quiescence loop, and a v2.0.0 release that ships all of it.
**Quality bar:** Nothing asserts what a test does not pin (the README's 11-vs-18 agents drift died untested once; never again). Every metric traces to a command (SPEC-073 AC2 house rule). Additive ledger markers share ONE convention (TOKENS + efficacy lines, same shape discipline). Boring, diffable, GitHub-native rendering; zero new dependencies.
**OSS-ready is the explicit intent (operator 2026-07-03):** this mega-goal's front-door work (SG-01 README/mermaid, SG-02 docs index, SG-08 v2.0.0 + the already-present LICENSE/CONTRIBUTING/CHANGELOG/MANUAL) must leave the repo readable by an EXTERNAL contributor, not just the operator , the README hero, install path, and command surface make sense cold. SG-01/02/08 each carry this lens; the understanding-gate mega-goal's SG-06 later ensures ITS additions do not re-muddy the front door.

**WIRING GATE (cross-cutting, operator 2026-07-03 , the anti-orphan rule).** kit-hardening's TIER-4 caught 3 agents that were defined + gated + rostered + documented but NOTHING dispatched them, and WORKFLOW.md OVER-CLAIMED them operational (fixed in `c6fbd99`). No sub-goal here is Done on "the artifact exists". Each new artifact must prove it is INVOKED by the live workflow, AND WORKFLOW.md must claim only what actually dispatches:
- **03 tokens:** a real orchestrated run's path CALLS `gate-ledger tokens` (not just the subcommand existing) AND `lane-telemetry report` surfaces it , proven by the captured run, not asserted.
- **04 tiers:** a fixture proves the DEFAULT tier is actually APPLIED at dispatch (the positive case), not only the override NC; `_route`/execute reads it.
- **05 provenance:** `draft-agent`'s install path EMITS `generated-by:` on a NEW generation (fixture), not just the backfill; metric 11 is in SPEC-073's runnable command set.
- **06 persona:** visual-team actually fires the 6th lens on `persona:` (fixture: 6 lenses dispatch), ui-design threads it.
- **07 done-modes:** ui-design consumes the `Done-mode` flag and branches (a fixture per mode reaches the right path).
- **09 role-agents:** EACH agent is dispatched by `execute.md` 2b-0's reuse branch , a task classified to its domain dispatches THAT agent (reuse hit), not a synthesized preamble. The wiring already EXISTS in 2b-0; 09's job is to make its agents discoverable by that lookup and prove the hit.
- **TIER-4:** the integration-verifier runs a no-orphan check over EVERY artifact this wave adds (agent, lens, subcommand, flag): defined-but-never-dispatched = a blocking finding; a WORKFLOW.md claim with no dispatch path = a blocking finding.
**Work repo:** `dwarves-kit` (sub-goals 04 + 07 each carry a small dotfiles-repo half: edit chezmoi source -> `chezmoi apply` -> stage+commit in ONE shell call, the S-64 watcher reverts uncommitted tracked changes).
**Stacking tool:** gh (stacked; 07 bases 06; everything else off `master`)
**Merge mode:** auto-bottom-up
**Merge autonomy:** gated-final (08-release is the final AND a `gate`: the loop prepares everything, never tags or publishes)
**Terminus:** build + merge + the held release PR; the tag + GitHub Release click is Han's.
**Started:** 2026-07-03

## Authority

Operator asks 2026-07-02/03 (production front, token efficiency, meta-agent check, designer-persona consult, UI done-modes) + the 2026-07-03 three-miner framing harvest (front-door / telemetry-tiering / UI). No single ADR; each sub-goal runs `/spec` + `/spec-validate`. Where a sub-goal amends recorded decisions (DEC-003 personas, meta-agent sonnet stance, SPEC-073 metrics), the amendment is IN scope and cited.

## Sub-goals

- [x] 01-readme-hero , README current + mermaid lifecycle replaces the ASCII hero; agents 11->18 fixed AND test-pinned , `auto` , PR #135 merged 9274b15
- [x] 02-docs-index , expand the existing 23-line docs/README.md into a thematic map (files stay put; no unpinned counts) , `auto` , PR #136 merged c1cd13e
- [x] 03-token-accounting , TOKENS ledger line (capture-gated) + lane-telemetry token section + per-lane render annotation , `auto` , PR #132 merged 6be7d9c
- [x] 04-tier-defaults , execute workers default mid-tier + template defaults `Model: sonnet` + meta-agent Mode B aligned (3 surfaces, one stance) , `auto` , PR #128 merged c4b6032
- [x] 05-provenance-efficacy , `generated-by:` backfill (5 agents, from their Source footers) + draft-agent emits it + SPEC-073 amendment: metric 11 = catches per generated agent , `auto` , PR #129 merged cf0dc73
- [x] 06-persona-lens , operator-supplied archetype as an inline 6th visual-team lens; DEC amending DEC-003's boundary + kit-health carve-out , `auto` , PR #130 merged f9981b4
- [x] 07-done-modes , ui-design Phase B gains quiescence mode (cap 3, stop = zero NEW >=HIGH and no OPEN >=HIGH) + Done-mode arg + coverage-delta row defined + template field , `auto` , PR #134 merged 2a3c021
- [x] 09-role-agents , meta-agent generates 8 role-specialized agents (one per `role-classify.sh` domain, MIXED reviewer/worker by fit), each gated by agent-effectiveness + provenance-stamped; reconciles SPEC-089; the meta-agent proof-of-function , `auto` , PR #133 merged 03620ac
- [x] 08-release-cut , v2.0.0: HELD-pair review round, ~24 PRs' changelog authored, 3-rename BREAKING map, 3 version surfaces bumped + pinned; tag/Release PREPARED , `gate` , PR #137 merged e375e57 (release content on master; v2.0.0 TAG + GH Release DEFERRED , Han cuts them when ready)

## Dependencies

- **Docs run LAST (operator 2026-07-03): 01 + 02 depend on ALL machinery (03, 04, 05, 06, 07, 09)** so the README diagram/agents-count and the docs index reflect FINAL state, not a mid-wave snapshot that 03-09 would immediately drift.
- 07 depends on 06 (quiescence rounds dispatch visual-team WITH the persona lens when supplied).
- 09 depends on none for building, but its generated agents feed 01's agents-count + 02's index (already covered by the docs-last rule).
- 08 depends on ALL (its changelog bullets need every merge SHA; cut at HEAD; runs after 01+02 so the release ships the refreshed docs).
- 03, 04, 05, 06, 09 are independent (the machinery wave; run first/parallel-ready).
- Execution order: {03, 04, 05, 06, 09} machinery -> 07 (needs 06) -> {01, 02} docs -> 08 release. Stack shape: machinery + 09 branch off `master`; 07 off 06's branch; 01/02 off `master` (after machinery merges); 08 off `master`, created last.

## Assumptions (harvest-resolved, 2026-07-03; operator AFK-defaults on the four asked)

**Operator questions (recommended answers baked):** persona lens proceeds with a DEC recording the boundary vs DEC-003 (runtime archetype ≠ baked persona) + a kit-health check-13 carve-out; token capture is CAPTURE-GATED (`--stream`/`DETERMINISTIC_HANDOFF` runs record TOKENS, others show `usage=?`, SPEC-087's default-path pin untouched); the sonnet default REVERSES the meta-agent Mode B stance consistently (template defaults `Model: sonnet`, Mode B writes sonnet-on-abstain, OMIT stays documented as deliberate inherit); 08 opens with a fresh-context review round on HELD #117 + #124, findings surfaced before any tag.

**01:** mermaid REPLACES the README ASCII lifecycle (WORKFLOW.md keeps ASCII canon); `docs/v-model.svg` linked from WORKFLOW.md, not embedded in README; 6-phase granularity, two gate classes (blocking/advisory); hero fold-in = one trust-story sentence (re-audit + advisor + deployable-done), NOT five feature bullets; add the agents-summary parity pin (same computed-pin shape as SPEC-085's hooks/commands pins); tighten = prose only, Credits intact.
**02:** keep the existing 23-line front door verbatim, extend below; thematic clusters + `lib/spec-index.sh` pointer for the 111 specs (no per-file rows); no counts (or pinned only); one central map, no new per-dir READMEs; `docs/verification/README.md` is LOAD-BEARING (ship-gate keys on it), link it, never move it.
**03:** TOKENS via a new `gate-ledger.sh tokens <rid> in= out= cache_read= cache_create= [cost=]` subcommand (single-writer + sanitization preserved); parser extends `lib/handoff/handoff_gen.py` (in-kit stream-json parser exists); metric schema borrows the v2 SG-09 12-col ledger vocabulary; rework-share at RUN granularity v1 (per-round needs a sidechain-usage probe first, one probe run in scope); render annotation is per lane/per run (median tokens-to-done), NOT per-phase (usage is per-session); watchdog path stays a declared gap v1; manual non-orchestrated runs report `usage=?` and deep dives point at ops-toolkit token tooling; thresholds pinned only after a 5-run baseline.
**04:** the "hard reasoning" escape hatch = an optional bare `Model:` header on the SPEC (absent -> workers dispatch sonnet); verifiers keep frontmatter tiers; the `sonnet|haiku|opus` lint stays as-is (agents deliberately never top-tier; one spec sentence acknowledges fable sessions inherit via SPEC-078 wording).
**05:** provenance one-liners derive from each agent's existing Source footer (all five first-committed 2026-07-02); test-meta tolerates the extra key (verified: no key whitelist); probe ONE backfilled agent loads in CC before committing all five; metric 11 v1 = CATCHES only (grep over docs/verification/* Re-audit lines + review records, AC2-compliant); the dispatch-count ACTION line is explicitly OUT (filed as a follow-up row, not scope creep); SPEC-073 gains an `## Amendments` entry, no new spec.
**06:** inline dispatch prompt (SPEC-016 "no new agent files"), borrowing code-reviewer's "through the X lens only" shape; `$ARGUMENTS` seeds a `Persona:` line in the `## UI design` brief (repeat runs read the brief); 0-or-1 persona per run, critique-only (persona-shaped GENERATION stays a non-goal, the brief's Tone fields own that); 6th `### Scores` row appended, verdict math already generic.
**07:** Done-mode is NOT skippable but is TIERED (operator 2026-07-03): `proof` is the mandatory default every UI sub-goal gets at least (real-surface flows + 2-3 captures + a11y); `over-test` and `quiescence` are OPT-IN escalations chosen per UI sub-goal at decompose time (proof if unspecified). quiescence EXTENDS ui-design Phase B (visual-team stays single-pass stateless); quiescence cap 3 (test-plan-review-team parity; plain REVISE keeps cap 2, recorded as a DEC); severity floor >=HIGH (kit has no MAJOR; one notch stricter than "only LOW remain", said explicitly); the loop lead carries the cross-round dedup ledger in-session, final critique carries `[[QL-VERDICT round=N ...]]` + `[resolved in round N | OPEN]` markers; stop = zero NEW >=HIGH AND no OPEN >=HIGH (a re-found unresolved CRITICAL must NOT quiesce); sub-floor + capped-out findings land in a `### Deferred findings` subsection of `## Visual critique` (kit-native; mega NOTES points at it); Done-mode declared in the sub-goal's Done= line, consumed as a `/kit:ui-design` `$ARGUMENTS` flag; over-test's coverage-delta = ACs-covered / tests-added before-vs-after, appended to the proof-of-done confirmation run-table.
**08:** cut at HEAD (ADR-0030 + SPEC-106 wavefront docs ride as a design-only Docs bullet); per-spec changelog bullets in the v1.7.0 house style, wave named per lead-in; BREAKING section = all THREE renames (integration-checker->integration-verifier, reviewer->code-reviewer, security-auditor->security-reviewer) with old->new map + a consumer-repo grep for stale references; bump VERSION + .claude-plugin/plugin.json + tool.toml (already drifted at 1.6.0) AND pin the three surfaces in test-meta; tag narrative + GH Release stay the manual convention (ship.md not extended); the loop PREPARES tag text + release body, Han executes.

**09 (RESOLVED , operator: both types, all 8 domains):** meta-agent placement VERIFIED correct 2026-07-03 (`commands/draft-agent.md` + `agents/meta-agent.md` present; installs to `~/.claude/agents/` by default, `--draft` staged-only, teammate reach PR-gated) , no move needed. Starter set seeds from `role-classify.sh`'s 8-domain taxonomy (security/db-migration/frontend/performance/data-etl/infra/api/generic), NOT invented. Each generated agent is gated by the SG-01/kit-hardening agent-effectiveness validator, so 09 is also the runtime proof-of-function for the meta-agent. DECIDED (operator 2026-07-03): BOTH types + ALL 8 domains , one agent per domain, type mixed across the 8 by fit (reviewer where judgment is the value, worker where doing is), NOT reviewer+worker each (that would be 16). Because this now includes static workers, it OVERLAPS SPEC-089 (dynamic synthesis) , 09 MUST reconcile the boundary (static-known roster vs dynamic-novel long tail), see goal file. Existing agents not duplicated.

**Cross-cutting:** 03 + 05 both add greppable record lines; ONE shared additive-marker convention sentence in each spec (TOKENS + efficacy lines match shape discipline). Wavefront (SPEC-106) is authored but UNBUILT: the orchestrator remains serial; nothing here depends on it.

## Audit cheat sheet

    grep -oE 'PR #[0-9]+' ROADMAP.md | sort -u | while read -r _ pr; do
      gh pr view "${pr#\#}" --repo dwarvesf/dwarves-kit --json state,reviewDecision,statusCheckRollup
    done
