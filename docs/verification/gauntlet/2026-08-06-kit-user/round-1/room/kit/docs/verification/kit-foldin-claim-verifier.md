# Proof of done: claim-verifier agent (kit-foldin SG-06)

**Sub-goal:** kit-foldin SG-06 (claim-verifier)
**Branch:** feat/kit-foldin-06-claim-verifier
**Artifact:** `agents/claim-verifier.md` (new kit subagent)
**Rung:** 3 (fresh-context recheck; LLM output is nondeterministic, so the claim is
"well-formed agent + a real dispatch returned a structured majority-vote verdict",
not an exact-value assertion).

## Design (bearing)

This sub-goal is a REDESIGN, not a file move. The predecessor
(`ops-toolkit/tools/verify-claim`) is a Python CLI that spawns N headless
`claude -p --model haiku` subprocesses, each a skeptic told to refute the claim, then
tallies a majority vote. The kit does not want a CLI or a subprocess panel; it wants a
first-class subagent dispatched like `kit:advisor`. So the mechanism is rebuilt.

### The fan-out contract (the durable decision)

| Dimension | Decision | Why |
|---|---|---|
| **N (panel size)** | default **3**, odd; overridable via dispatch prompt | odd -> unambiguous majority, never a tie; 3 is cheap enough for an on-demand check; matches the predecessor's default |
| **Threshold** | `HOLDS` iff `refuted * 2 <= N`, else `REFUTED` (holds unless a MAJORITY refute) | identical to `verify-claim` (`refuted*2 <= n`); pairs a paranoid per-skeptic posture with a majority aggregate so one paranoid skeptic cannot flip the verdict |
| **Dispatch style** | **single dispatch, N in-context independent skeptic passes, aggregated in-agent** | a subagent cannot dispatch sub-subagents (harness disallows subagent recursion) and must not shell out to `claude -p` (the replaced mechanism); the fan-out is in-harness and in-context |
| **Independence** | each skeptic reasons FRESH from a DISTINCT attack angle (N=3: factual/empirical, logical/definitional/scope, steelman-then-break; N>3 adds provenance, then adversarial-counterexample) | cross-angle diversity is the in-context substitute for cross-model diversity; a re-vote from the same angle adds nothing |
| **Fail-closed** | a skeptic returns `refuted=true` on any of: claim false/unsupported/overstated, unverifiable, or a hedged/garbled/tool-error judgment | any doubt is a refutation; a broken pass can never yield a false HOLDS (matches `verify-claim`'s fail-closed parse) |
| **Cross-model** | honored where the harness allows | see below |

### Cross-model (Omnigent Polly property), and its honest boundary

The RIDE-LATER (NOTES ## Proposed additions, Omnigent row 9) asks the panel to default
cross-model with the claim's producer. The predecessor CLI could do this trivially
(each `claude -p` is a separate process, free to pick a model). A single subagent runs
a single model, so true cross-VENDOR diversity is NOT reachable from inside one
dispatch. The redesign honors the property as far as one dispatch allows and records
the boundary rather than over-claiming it:

1. **Cross-angle independence** stands in for cross-model diversity within the context.
2. **Cross-tier by default:** the agent's `model:` is `sonnet`, deliberately not the
   `opus` a writer/lead typically runs on, so the panel is not the same configuration
   that produced the claim.
3. **Escalation the harness DOES allow:** a caller wanting true cross-vendor review
   dispatches this agent AND a different-vendor skeptic separately and compares. That is
   a caller-side choice, out of this single dispatch's scope; documented so a future
   multi-runtime kit wires it without redesigning the agent.

### Tools + tier (the agent-effectiveness surface)

- **Tools:** `Read, Grep, Glob, Bash(git diff*), Bash(git log*)` -- the read-only
  verifier set (mirrors `advisor`). It lets a skeptic inspect repo evidence for a
  codebase claim ("function X handles Y", "the migration is reversible"). NO `Write`/
  `Edit` (it judges, it does not fix -- ADR-0005 read-only-verifier contract). NO
  `Agent`/`Task` (a subagent cannot fan out subagents; granting it would be an
  over-grant the effectiveness lens flags). NO `WebFetch`/`WebSearch` (the design is
  "try to break, fail-closed if unverifiable", not "research the claim into truth").
- **Model:** `sonnet`. Adversarial refutation is genuine judgment (subtle correctness,
  definitional traps), so `haiku` under-tiers it; it is not architecture-scale hard
  reasoning, so `opus` over-tiers and burns the expensive tier on an on-demand check.
  `sonnet` is the cheapest tier that can decide the hardest case (cheap-first,
  WORKFLOW.md verification cost routing).

### Gap it fills (why a new agent, not a dup)

Confirmed (design note open-Q 2, RESOLVED) that no existing kit verify-shaped agent
judges an arbitrary claim: every one re-executes or critiques a SPECIFIC artifact
(task vs command, spec vs diff, doc vs code, a recorded PASS vs a fresh run). This is
the semantic half of the citation-guard hook, which only checks a cited `file:line`
EXISTS, never whether the surrounding assertion is TRUE.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| AC1 | `agents/claim-verifier.md` has valid kit frontmatter (name, description, tools, model in `sonnet\|haiku\|opus`) and a MANUAL.md roster row | PASS -- `tests/test-meta.sh` 679/679 |
| AC2 | A fixture claim (clearly-false) is committed under `tests/fixtures/` | PASS -- `tests/fixtures/claim-verifier/false-claim.json` |
| AC3 | A REAL dispatch on the fixture claim returns a well-formed STRUCTURED majority-vote verdict | PASS -- REFUTED 3/3, well-formed block (see Confirmation run) |
| AC4 | `kit:agent-effectiveness` lens over the new def returns a non-FLAGGED verdict (tools minimal-yet-sufficient, description fires right, instructions unambiguous, tier fits) | PASS -- all four lenses OK (see Confirmation run) |

## Confirmation run

### AC1 -- structural gate (test-meta.sh)

```
$ cd dwarves-kit && bash tests/test-meta.sh | tail -3
=== Results ===
Passed: 679 / 679
All meta tests passed.
```

Includes the 6 claim-verifier rows: frontmatter present, `model` = sonnet (valid
enum), MANUAL.md row present (both directions), name is not a retired suffix,
architecture.md + README counts match live file count.

### AC3 -- smoke: real dispatch returns a well-formed structured majority-vote verdict

A fresh-context worker was dispatched with the agent's full instruction body as its
prompt and the fixture claim (`tests/fixtures/claim-verifier/false-claim.json`:
"Water boils at 10 degrees Celsius at standard sea-level atmospheric pressure.").
Real model dispatch, 6.9s, returned EXACTLY the structured block the agent specifies:

```
VERDICT: REFUTED
Panel: N=3, refuted=3/3, threshold=majority-refute (REFUTED iff refuted*2 > N)
Claim: Water boils at 10 degrees Celsius at standard sea-level atmospheric pressure.
Skeptics:
  1. [Factual/empirical] refuted=true -- Pure water boils at 100 C at 1 atm (101.325 kPa), not 10.
  2. [Logical/definitional/scope] refuted=true -- At 10 C water is a stable liquid far below its
     boiling point, contradicting the definition of the normal boiling point.
  3. [Steelman-then-break] refuted=true -- No steelman survives: 10 C boils only under near-vacuum
     (~1.2 kPa), the opposite of the stated standard sea-level pressure.
Basis: reasoned from established physical-chemistry knowledge; claim is decisively false.
```

Well-formed (matches the mandated block), three DISTINCT skeptic angles as designed,
fail-closed majority tally correct (`refuted*2 > N` -> REFUTED), verdict = the fixture's
expected `REFUTED`. This is a REAL dispatch, not a described intention. (Nondeterministic
by nature; the proof is the well-formed structured block + correct majority mechanics,
not an exact-value assertion.)

### AC4 -- kit:agent-effectiveness lens

Dispatched `kit:agent-effectiveness` (a real subagent dispatch, 2 tool uses, 44.7s)
pointed at `agents/claim-verifier.md`, calibrated against `agents/recheck-verifier.md`.

```
VERDICT: PASS
Lenses: tools OK, description OK, instructions OK, tier OK
Agent: claim-verifier (sonnet)
```

Per-lens: (1) tools scoped read-only, no over-grant, no missing capability -- the
"unverifiable -> fail-closed" fallback makes the absence of web/network tools a
deliberate design choice, not an unbacked promise; (2) description scoped to
load-bearing claims with concrete triggers AND explicit self-differentiation from
citation-guard + recheck-verifier (forecloses the two nearest misfire cases); (3) the
majority-vote formula is stated consistently 3x, fail-closed + infra-error handling
unambiguous, a representative "X faster than Y" claim gets a determinate outcome; (4)
sonnet fits genuine adversarial judgment, justified as a deliberate cross-tier choice.
The "independent skeptics in one context" tension was judged HONEST scoping (disclosed
in the Cross-model section), not a contradiction. No defect met the finding bar.

## Reproduce

```
# structural gate
cd dwarves-kit && bash tests/test-meta.sh          # 679/679, incl. the 6 claim-verifier rows

# smoke: dispatch the agent's instructions on the fixture claim (a fresh general-purpose
# context, since the new def is not yet in the session's agent registry), capture the
# structured verdict block. On install, the same is reachable as subagent_type claim-verifier.

# effectiveness: dispatch kit:agent-effectiveness pointed at agents/claim-verifier.md
```

## Notes

- The predecessor `ops-toolkit/tools/verify-claim` is retired by SG-07 (status=moved ->
  kit agent), not by this sub-goal.
- Smoke method: the new agent def is not in this session's startup-loaded registry, so the
  smoke dispatches the agent's full instruction body as a fresh-context worker prompt on
  the fixture claim -- a real model dispatch producing a real structured verdict, which is
  exactly what a `subagent_type: claim-verifier` dispatch will do once installed.
