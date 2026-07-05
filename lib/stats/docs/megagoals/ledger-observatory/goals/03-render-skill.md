# Sub-goal 03: render skill (terminal OR web Artifact)

**Merge policy:** auto
**Time budget:** 3-4 hours.
**Proof:** run-table: the skill fires on "show me the ledger state / my debt / telemetry / token cost" (trigger match) · it queries via the 02 `ledger` CLI (not a re-implementation) · it renders IN-TERMINAL using bot-reply-formatting (tables/bars) · it renders a web ARTIFACT (claude.ai) for share/review · negative control: BOTH surfaces render from the SAME 02 query output (no divergent second data path). Capture a terminal-render sample + an Artifact screenshot/HTML.
**Depends on:** 02.
Model: sonnet
Effort: high
**Branch:** feat/lo-03-render
**PR base:** feat/lo-02-etl-cli

## Outcome

A skill (SKILL.md, the ops-toolkit skills gradient) that fires when the operator asks to SEE ledger state , "show me the ledger state", "my debt", "telemetry", "token cost", and kin , QUERIES via the 02 `ledger` CLI (never re-implements the read), and RENDERS the result in one of two surfaces: (a) IN-TERMINAL via `bot-reply-formatting` (tables + bar-fills, phone-legible) for a quick agent reply, OR (b) a shareable web ARTIFACT (claude.ai) for review/share. The skill picks the surface by intent (quick look = terminal; share/review = Artifact). This is the human-facing lens the operator drives THROUGH the agent , no TUI, no app.

## Quality bar

It COMPOSES , queries 02's structured output + formats via bot-reply-formatting / the Artifact tool , it does NOT re-query the ledgers directly (one data path, 02). Both surfaces render from the SAME 02 output (the NC). Terminal output is phone-legible (bot-reply-formatting discipline); the Artifact is self-contained (CSP-safe, inline assets).

## How to close the loop

`/spec` + `/spec-validate` first (pin the trigger set + the surface-selection rule; write a `## Design` block if design-bearing). Then `bash tests/test-render-skill.sh`: the trigger-fires assertion, the queries-via-02 assertion (a mocked CLI output in, a formatted surface out), the terminal render, the Artifact render, and the single-data-path NC. Capture a terminal-render sample + an Artifact screenshot/HTML in the proof. Assumptions: ROADMAP 03.

**Done =** the skill fires on its triggers, queries via the 02 CLI, renders BOTH a terminal (bot-reply-formatting) and a web-Artifact surface from the same 02 output (single-data-path NC), samples captured, tests green.

## Scope edges

**In:** the render SKILL.md + its trigger set, the 02-CLI query call, the bot-reply-formatting terminal render, the Artifact render, tests + captured samples.
**Out:** the CLI itself (02); the anomaly/feedback loop (04); the README wiring (05).
**Not:** a re-implementation of the ledger read (query via 02, one data path); a persistent TUI/app (agent-driven + Artifact only); a divergent second data source for the Artifact.

## Where to look

the `bot-reply-formatting` skill (terminal tables/bars), the `Artifact` tool (the web share surface), existing read-only-tool skills that wrap a CLI (`icy-ops`, `growatt-solar`, `asus-mesh` , the skill-over-CLI shape), SG-02's `ledger` CLI output contract, the research Addendum's render fan-out (terminal + Artifact).

## PR body

Render skill (the human-facing lens): fires on "show me the ledger state / my debt / telemetry / token cost", queries via the 02 `ledger` CLI, and renders EITHER in-terminal (bot-reply-formatting) OR as a shareable web Artifact , both from one 02 data path. Stacked on #<02's PR>; review after it. Verify: `bash tests/test-render-skill.sh` (trigger + queries-via-02 + both-surfaces + single-data-path NC) + captured samples. Roadmap: ops-toolkit `_meta/megagoals/ledger-observatory/ROADMAP.md`.

## Notes

<empty>
