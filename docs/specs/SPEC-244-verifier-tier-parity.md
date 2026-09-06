# Spec: a verifier is never dumber than its worker

Generated: 2026-09-06
Status: VALIDATED (normal lane: the spec-validate phase is skip per the lane matrix)
Lane: normal
Type: spec-feature
File: `docs/specs/SPEC-244-verifier-tier-parity.md`
References: `docs/specs/SPEC-107-tier-defaults.md` (the cheap-first worker default and the wall-off sentence this spec supersedes for verifiers); `commands/execute.md:159-166` (the worker tier rule); `commands/review-team.md:46-53` and `commands/battery.md:24-28` (the precedent for a dispatch-time override above an agent's frontmatter); `agents/recheck-verifier.md` (the false-PASS backstop).

## Problem

SPEC-107 made `sonnet` the cheap-first worker default and gave a spec one escape hatch: a bare `Model: opus` header dispatches that spec's workers on opus. The same paragraph walls verifiers off: "Verifiers keep their own frontmatter tiers (unchanged)."

Every verifier is `model: sonnet`. So a spec hard enough to earn `Model: opus` gets opus workers and sonnet judges. The judge is then structurally weaker than the thing it judges. A verifier that cannot follow the worker's reasoning cannot catch the worker's mistake, and its PASS is worth less than the run that produced it.

`recheck-verifier` carries the sharpest version of the problem. It is the only agent that re-audits another verifier's PASS, so a false PASS that survives it is never caught again. It runs once per verified task, so its volume is low and its tier is cheap to raise.

## Decision

**A verifier is never dumber than its worker.** Three parts.

**(a) Spec-tier parity at dispatch.** When the active spec carries the bare `Model: opus` header, every verifier dispatched for that spec (task, recheck, integration, acceptance, system) is dispatched with an explicit `model: opus` override. Absent a `Model:` header, verifiers keep their frontmatter default. The dispatch-time override above frontmatter is the review-team pattern, and it carries the same graceful-degrade clause: if the override is unavailable in the dispatch surface, omit it and note that.

**(b) `recheck-verifier` pins `model: opus` unconditionally.** It is the false-PASS backstop and it runs once per verified task, so the volume is low and the cost is bounded. Its tier does not depend on a spec header, because a fabricated PASS is equally expensive on a cheap spec.

**(c) Everything else is deliberately unchanged.** Reviewers and research agents keep their current tiers: they read a diff or a codebase, they do not adjudicate a worker's claim, and `review-team` already tiers its own high-stakes lens at dispatch. `research-stack` stays haiku. `doc-verifier` stays sonnet: it runs in the docs phase against a doc diff, not against a spec, so no spec tier binds it. Nobody should "fix" these later without a new decision.

## Scope and non-goals

In scope: `agents/recheck-verifier.md`, `commands/execute.md`, `commands/verify.md`, `commands/battery.md`, the SPEC-107 wall-off sentence, and the `tests/test-meta.sh` pins.

Non-goals: no change to worker tiering, no change to reviewer or research tiers, no new lane, no `lib/` or `hooks/` edit, no machine-enforced reader. The dispatch surfaces are prompts, so the policy is instruction prose, grep-pinned, the accepted SPEC-078 fidelity.

## The exact changes

| File | Change |
|---|---|
| `agents/recheck-verifier.md` | frontmatter `model: sonnet` becomes `model: opus` |
| `commands/execute.md:162-163` | the wall-off sentence is replaced by the parity sentence carrying the phrase `dispatch with an explicit model override matching the spec tier` plus the graceful-degrade clause |
| `commands/execute.md` 2c, 2c-1, Step 4 | one short override note at each of the three verifier dispatch sites |
| `commands/verify.md` Step 1 | the resolve step reads the spec's bare `Model:` header |
| `commands/verify.md` Steps 3-6 | the conditional override, stated once with the same verbatim phrase |
| `commands/battery.md:24-28` | the acceptance leg's model cell becomes "mid, or the spec's tier when it carries `Model: opus`" |
| `docs/specs/SPEC-107-tier-defaults.md` | a one-line "Superseded by SPEC-244 for verifiers" note next to the wall-off sentence; history is not rewritten |
| `commands/docs.md` | unchanged, per decision (c) |
| `tests/test-meta.sh` | a SPEC-244 block: the frontmatter pin, the two parity-phrase pins, the wall-off negative control |

## Verification

```bash
cd dwarves-kit
# (b) recheck-verifier pins opus
awk -F': *' '/^---$/{c++; if(c==2)exit} c==1 && /^model:/{print $2}' agents/recheck-verifier.md   # opus

# (a) the parity phrase is present in both dispatch surfaces, verbatim
grep -qF 'dispatch with an explicit model override matching the spec tier' commands/execute.md
grep -qF 'dispatch with an explicit model override matching the spec tier' commands/verify.md

# negative control: the old wall-off sentence is GONE, not merely supplemented
! grep -qF 'Verifiers keep their own frontmatter tiers (unchanged).' commands/execute.md

# (c) doc-verifier and the reviewers are untouched
grep -q '^model: sonnet$' agents/doc-verifier.md

bash tests/test-meta.sh   # green, incl. the SPEC-244 block and the agent-frontmatter lint
```

## Test plan

| # | Case | Covers | Proof |
|---|---|---|---|
| 1 | `recheck-verifier` frontmatter is `opus` | (b) | `grep -q '^model: opus$' agents/recheck-verifier.md` |
| 2 | `opus` is still a legal frontmatter value | (b) | `bash tests/test-meta.sh` agent-frontmatter lint block |
| 3 | execute.md states the parity override | (a) | `grep -qF '<parity phrase>' commands/execute.md` |
| 4 | verify.md states the parity override | (a) | `grep -qF '<parity phrase>' commands/verify.md` |
| 5 | verify.md reads the spec `Model:` header | (a) | `grep -qiE 'bare .?Model:.? header' commands/verify.md` |
| 6 | the wall-off sentence is removed | (a) | `! grep -qF 'Verifiers keep their own frontmatter tiers (unchanged).' commands/execute.md` |
| 7 | the graceful-degrade clause survives | (a) | `grep -qiF 'if the override is unavailable' commands/execute.md` |
| 8 | battery's acceptance leg names the spec tier | (a) | `grep -qF 'or the spec' commands/battery.md` |
| 9 | doc-verifier stays sonnet | (c) | `grep -q '^model: sonnet$' agents/doc-verifier.md` |
| 10 | negative control: reverting (b) to sonnet turns the suite red | (b) | edit, run `bash tests/test-meta.sh`, expect FAIL, restore |

## After state

- `agents/recheck-verifier.md` is `model: opus`.
- `commands/execute.md` and `commands/verify.md` both carry the parity sentence verbatim; execute.md no longer carries the wall-off sentence.
- `commands/battery.md` acceptance leg names the spec tier.
- `docs/specs/SPEC-107-tier-defaults.md` points at this spec for the verifier half.
- `tests/test-meta.sh` carries the SPEC-244 block, and `docs/verification/verifier-tier-parity.md` carries the run-table plus the negative control.
