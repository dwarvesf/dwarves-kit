# Sub-goal 09: onboard-wizard

**Merge policy:** gate
**Time budget:** 1 day of loop work
**Proof:** (SPEC-199) 3 recorded walkthrough transcripts (captured text, committed under docs/proof/): (a) fresh plugin-only machine, (b) bash-install machine with an unadopted repo, (c) already-adopted repo (wizard reports healthy + exits without writing); plus the never-writes-without-confirm NC (a declined prompt leaves a byte-identical tree, diff captured). Rung 3: a fresh-context recheck-verifier RE-EXECUTES scenario (b) live (a hand-crafted transcript is this mega's most fake-able artifact; the kit-foldin precedent assigns rung 3 to interactive surfaces), before Han's gate review.
**Design:** bearing (a new interactive flow; the fences are ADR-0034 §4)
**Done-mode:** proof
**Depends on:** 08
Model: opus
**Branch:** `feat/loop-09-onboard-wizard`
**PR base:** `feat/loop-08-config-surface` (stacked; review after SG-08)

## Touches

commands/ (new onboard.md), possibly a small lib/ helper for detection, docs/MANUAL.md (one section), tests/ (detection helper only; the interactive flow is proven by transcripts)

## Outcome

`/kit:onboard` is the first ten minutes, guided: detects install mode (plugin / bash / none / BOTH-with-double-hooks, each with its one-line explanation), offers `/kit:adopt` for the cwd repo, walks module selection (bridging the plugin path's missing `--with`, writing the choices via the existing install/adopt mechanics), captures the consumer knobs that make chosen modules non-inert into `.kit.toml` + printed env guidance, the knob list GENERATED from SG-08's registry (e.g. `bin/config list --status consumer` filtered to the chosen modules), never a second hardcoded list, so a knob added to the registry later shows up in the wizard with zero edits, discloses plugin-path gaps honestly (statusLine, frozen SHA, KIT_FORCE_FULL escape), and ends with the welcome tour: the five-leg loop in five sentences + `/kit:start` as the next step. Every write is previewed and confirmed; decline = no-op. start/adopt/config keep their fenced jobs (ADR-0034 §4): the wizard ORCHESTRATES, it never reimplements detection or injection.

## Quality bar

Feels like the kit introducing itself, not a form. Each question carries a recommended default so Enter-Enter-Enter produces a sane setup; an expert can answer five questions in sixty seconds; a decline never punishes. Honest about what the plugin path cannot do.

## How to close the loop

1. Spec (SPEC-199) with the flow as a state diagram in the Design block; /kit:spec-validate.
2. Build; drive the three scenarios (temp HOME + fixture repos for a/b; this repo for c); capture full transcripts.
3. NC: scenario b declining every prompt; `git status --porcelain` + tree hash before/after identical, captured.
4. Dispatch `kit:advisor` critique on the transcripts (P5: misleading copy, fence violations); apply findings.
5. Open the PR, emit the approval banner, STOP for Han (gate: UX taste).

**Done =** three transcripts + decline-NC committed + advisor pass recorded + PR open and HELD for Han.

Kit-adopted repo: record gates via `bash lib/gate/gate-ledger.sh` per lane plan before the PR push.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. HANDOFF.md: next = 10 once 05 + 07 are merged; first action = the README five-leg outline from ADR-0034 §3's table. 3. DECISIONS.md: the question list + defaults chosen. 4. EXIT.

## Scope edges

**In:** the command, detection reuse, transcripts, MANUAL section.
**Out:** install.sh changes (stays non-interactive by decision), adopt.sh changes, any new module.
**Not:** an update/upgrade wizard (INSTALL-STAMP staleness surfacing is one printed line + a pointer to kit-health, not a flow), telemetry/analytics of wizard answers, a TUI framework.

## Where to look

commands/start.md + lib/adopt.sh + install.sh's plugin-detect block (`install.sh:315-353`) for the detection primitives; SG-08's `bin/config` for the knob explanations; ADR-0009 (dual-ship truths the copy must state); docs/consumer-contract.md (what adopted means).

## PR body

`/kit:onboard`: guided first-run (mode detect, adopt offer, module pick, consumer knobs, plugin-gap disclosure, five-leg tour); previews + confirms every write, decline = no-op. Verify: 3 committed transcripts + decline-NC. GATED for UX review. Roadmap: `_meta/megagoals/harness-loop/ROADMAP.md` SG-09.

## Notes
