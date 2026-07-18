# Decision Brief: behavioral-test tiering (cheap-but-honest AI-app tests)

Date: 2026-07-17 · Source: neko-anon Hermes-bot permtest suite (dfoundation);
generalization request from Han. Full playbook: ops-toolkit
`research/2026-07-17-behavioral-test-cost-optimization.md`.

## Verdict: BUILD (v1 = the test-plan/test-generation lane emits tiers, not a runner)

## Core thesis
When the kit generates a test plan for AI-in-the-loop software (an agent, a
bot, an LLM feature), it should structure cases into COST TIERS and teach the
harness three cheap-failure ergonomics, so the suite is cheap enough to run
often without lowering the real-model floor. The pattern is proven in one
hand-built suite; the kit is where it becomes a default for every AI-app test
plan it produces.

## The pattern (proven on neko-anon, PR #145)
A behavioral test that triggers a real model has two costs: wall time (a serial
lap is minutes, not the dollars people expect) and a flake tax (substring
grading on free-text output flakes; one transient miss + a lost failure-name
cost two full re-run laps). Four green-while-broken incidents on the same bot
established the floor rule: **config asserts lie; a behavior claim keeps a
real-model probe.** So the optimization is tiering each CLAIM to its cheapest
honest home, never deleting the behavioral floor.

Five levers (first three shipped in permtest, measured):
1. **Tier each claim.** Mechanical claims (dep baked, file exists, parser
   correct, engine returns move X) drop to a no-model self-check or a config
   assert; only "the live model, asked in NL, does Y" stays behavioral.
2. **Smoke tier on a cheap model** for iterating on GRADING rules, never a ship
   gate (a proxy model is not the system under test). Ranking: kimi-k2.6 →
   glm-5.2.
3. **Cheap failure ergonomics**: a failed-ids summary (survives a piped run) +
   retry-once scoped to benign phrasing misses ONLY (a security verdict is
   never retried; eligibility is an allowlist so new failure types are
   non-retryable by default).
4. **Diff-keyed selection** (case → files map; run touched cases + a containment
   core per branch, full suite pre-merge). Highest remaining win, not yet built.
5. **Parallelism** for the independent read/answer cases (serial only for
   shared-state side-effect cases).

## Strongest argument for
The kit's whole job is generating right-sized process for a work type. "AI app
with real-model tests" is a work type it will hit constantly, and today it has
no opinion on making those tests affordable, so every consumer re-derives this
(or, worse, runs the suite rarely and loses the regression net). Encoding the
tiering once pays every AI-app test plan forward.

## Strongest argument against
Only one real datapoint (neko-anon). The levers may be Hermes-permtest-shaped,
not universal. Risk of building a general mechanism ahead of a second consumer.
Mitigation: v1 ships as GUIDANCE in the test-plan lane (a tier taxonomy + the
floor rule + the smoke/retry doctrine the generator emits), not a runner; a
concrete runner waits for a second consumer to confirm the shape.

## Forcing-question findings
- **What is the actual pain?** Wall time and flake tax, not dollars. A suite
  too slow/flaky to run often silently stops catching regressions. The bar is
  "cheap enough to run more", not "cheaper".
- **What must never regress?** The real-model floor. The failure mode to design
  against is a consumer "optimizing" by deleting behavioral cases or letting a
  cheap-model smoke run gate a ship. The generated guidance must state both as
  hard don'ts.
- **Where is the leverage?** The test-plan / test-generation lane
  (`/kit:test-plan`, the test-design review team), NOT a new runner. The kit
  emits tiers + doctrine; the consumer's own harness runs them.
- **Exit criterion (pre-register):** a generated AI-app test plan (a) assigns
  every case a tier with a one-line "why this tier is honest", (b) carries the
  floor rule + the two hard don'ts verbatim, (c) marks which cases are
  smoke-eligible and which are security/side-effect (never-retry, never-smoke).
  Negative control: a plan that puts a boundary claim in the config tier is
  rejected by the test-plan review team.

## If BUILD: recommended v1 scope
- **SG-1 (guidance):** a tier taxonomy + the floor rule + smoke/retry doctrine
  injected into `/kit:test-plan` output for AI-in-the-loop work types. The
  generator classifies each proposed case into a tier and states the honesty
  reason.
- **SG-2 (review lens):** the test-plan review team gains a "tiering + floor"
  lens: flags a behavior/security claim parked below the behavioral tier, and a
  smoke run used as a gate.
- **SG-3 (defer):** a reference runner (selection + parallel + retry + smoke
  flags) only after a second consumer. Point consumers at the permtest
  implementation as the worked example until then.

## Sequencing
Independent of the naming/plain-words work in flight. Couples to whatever work
type taxonomy `/kit:test-plan` already uses; slots in as an AI-app profile.
No ADR needed for v1 (guidance + a review lens, no done-definition change);
SG-3 would get one if/when a runner is built.
