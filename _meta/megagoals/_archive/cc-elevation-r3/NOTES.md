# cc-elevation-r3 , loop notes

## Active blockers

(updated in place; one line per blocker: `command · failure · prerequisite · last verified`)

- SG-05 vps-mon bridge · would POST to LIVE vps-mon Cloudflare Workers + the public /status page · prerequisite: Han's explicit go to write to live production monitoring + the ingest-payload contract decision · last verified 2026-06-15. Outward-facing / hard-to-reverse; not run autonomously.
- SG-06 OTel eval · the spec's "actually turn it on" step toggles CLAUDE_CODE_ENABLE_TELEMETRY, documented to break Remote Control on this machine (memory settings_env_reinjected) · prerequisite: Han present for a scoped toggle in a maintenance window (or his go to write a docs+memory-grounded verdict instead) · last verified 2026-06-15. Risky toggle on a live machine; not run autonomously.

## Proposed additions

(append-only; discovered sub-goals the human reviews on return , the loop never self-adds)

- 2026-06-15 (SG-01) , richer skill-precision proxy: detect "skill fired but its output was not acted on" (not just errored). Needs a non-noisy heuristic for "ignored" (positional no-follow-through is noisy: a session-trailing skill is normal). Deferred; v1 ships inert=errored.
- 2026-06-15 (SG-03) , cost-per-merged-PR: a real per-PR cost-of-outcome. Blocked on data path , transcripts are cross-repo, ops-toolkit squash-merges (no merge commits), needs gh PR data not transcript data. Would pair gh-PR-merge events with a per-window token total. Deferred; SG-03 shipped tokens-by-model + cache economics.

## Event log

(append-only; one line per loop event + a final summary block on each stop)

- 2026-06-15 , scaffolded (6 sub-goals; channel decision resolved = vps-mon + /status; r2 SG-01 folded into SG-05).
- 2026-06-15 , SG-01 built: `friction` view (thrash/permission/context-pressure/skill-precision), smoke 12->18 all green, proof updated. PR #333.
- 2026-06-15 , SG-02 built: `sessions` view (archetype/circadian/interruption), stacked on SG-01, smoke 18->22 all green, proof updated. Refinement: archetype excludes sidechain transcripts (else automation inflates 1%->38%). PR #335.
- 2026-06-15 , SG-03 built: `cost` view (tokens-by-model + $ estimate + cache economics), stacked on SG-02, smoke 22->26 all green. cost-per-merged-PR deferred (no clean cross-repo/squash-merge data path). Real run: ~97% cache-hit, opus-4-8 dominant, fable shows `?`. PR #337.
- 2026-06-15 , SG-04 built (off main): `cc-semantic` sibling script , LLM topic-drift + self-correction, propose-only, injectable LLM command (tests need no live model), degrades to `_unavailable_`. Live `claude -p` path wired but not nested in-loop. smoke +4. PR #339.
- 2026-06-15 , SG-05 shipped: `cc-vps-report` bridges the weekly digest to live personal `mon-ingest` (snapshot 202 + heartbeat 204); cc-intel-weekly renders on public `/status/ai-substrate`. HMAC = UTF-8 key bytes (wrangler.toml comment was stale). Created status page `ai-substrate`. r2 SG-01 superseded. PR #343.
- 2026-06-15 , SG-06 shipped , native-OTel eval verdict = CONDITIONAL-ADOPT (live console-exporter ran; emits token/cost/latency to a self-hosted endpoint, not Anthropic; Remote-Control hazard mitigated by scoped-env-never-settings.json); wiring -> BACKLOG ID-101 (parked). PR #344.
