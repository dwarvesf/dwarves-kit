# Sub-goal 06: native OpenTelemetry eval

**Time budget:** ~2-3h · **Depends on:** none · **Branch:** feat/cc-elev-r3-06-otel-eval · **PR base:** main

## Outcome

A documented adopt-or-skip decision on Claude Code's **native OTel** as a complement to the
transcript-parsing approach: `CLAUDE_CODE_ENABLE_TELEMETRY=1` emits token/cost/model-latency spans
+ metrics over OTLP, which could feed vps-mon directly with zero JSONL parsing. This sub-goal is an
**eval**, its deliverable is a decision + a research-note section, not necessarily a wired pipeline.

## Quality bar

Eval-first: actually turn it on in a throwaway/controlled way and observe what it emits, do not
decide from docs alone. **Hard caveat to test explicitly:** the `settings.json` env block has
broken Remote Control before (the `DISABLE_TELEMETRY` interaction, memory `settings_env_reinjected`)
, verify enabling telemetry does NOT regress Remote Control or re-inject a bad env. If adopt: the
exporter target is vps-mon's collector (reuse, no new stack like SigNoz/Grafana). If skip: say why
(redundant with transcript parsing, privacy, or the env-block risk).

## How to close the loop

- Enable telemetry in an isolated way (a scoped env, not the global `settings.json` first), observe the OTLP output (console exporter is fine for the eval).
- Test the Remote Control regression explicitly (the documented failure mode).
- Map what native OTel gives that transcript-parsing does NOT (and vice-versa): latency spans, real-time vs batch, token counters.
- Write the decision into `research/2026-06-15-claude-code-usage-metrics-and-tooling.md` (a new "Native OTel eval" section) with the verdict + rationale + the Remote-Control test result. If adopt, a follow-up wiring row goes to BACKLOG (not done here).

**Done =** a recorded eval (what OTel emits, the Remote-Control regression test result, OTel-vs-transcript delta) ending in a written adopt-or-skip verdict in the research note; if adopt, a BACKLOG row for the wiring; on PR #NN.

## Scope edges

**In:** turning OTel on in a controlled way, observing output, the Remote-Control regression test, the written verdict.
**Out:** a full production OTel pipeline (that is a follow-up only if the verdict is adopt); the transcript-parsing views (01-04); the vps-mon /status bridge (SG-05).
**Not:** flipping global `settings.json` telemetry without the regression test; adding SigNoz/Grafana/Datadog; deciding from docs alone.

## Where to look

[Anthropic OTel docs](https://docs.anthropic.com/en/docs/claude-code/monitoring-usage), the research note's OSS-landscape row (native CC OTel + claude-code-otel/cc-metrics), memory `settings_env_reinjected` (the Remote-Control failure mode), `tools/vps-mon/` (would-be collector target), dotfiles `modify_settings.json` (where the env block lives, do NOT edit it for the eval, use a scoped env).

## PR body

Outcome: eval of native Claude Code OTel as a vps-mon feed; documented adopt-or-skip verdict.
Verify: OTLP output observed; Remote-Control regression explicitly tested; verdict written into the research note.
Roadmap: `_meta/megagoals/cc-elevation-r3/ROADMAP.md` (sub-goal 06).
