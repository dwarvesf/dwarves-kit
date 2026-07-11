# Sub-goal 10: front-door-truth

**Merge policy:** auto (held as the FINAL PR under gated-final; Han's click closes the mega)
**Time budget:** 3-6 hours of loop work
**Proof:** parity run-table: agents-table rows == `ls agents/*.md | wc -l` (25), skills rows == count of `skills/*/SKILL.md` (2; `lib/stats/skill/SKILL.md` is a subsystem-internal skill, explicitly OUT of the top-level skills table, the parity test says so), commands rows == live count, each greppable and captured; a rendered README section screenshot (the five-leg diagram via GitHub-native mermaid); the generated intel-file fixture showing the digest scorecard section; the consumer LaunchAgent runbook present with its plist template. Rung 2. This is a cohesion REWRITE of the README narrative: /kit:pitch discipline (outcome-first, delete stale narrative, never append-only).
**Design:** obvious (the taxonomy is ADR-0034; this renders it)
**Depends on:** 05, 07, 08, 09
Model: opus
**Branch:** `docs/loop-10-front-door`
**PR base:** master

## Touches

README.md, docs/architecture.md (counts + loop section pointer), docs/MANUAL.md (leg-organized command index), lib/session/intel (digest fold), deploy templates for the weekly LaunchAgent (kit-side template; consumer instantiates), RUN_REPORT.md + close-out artifacts for the whole mega

## Outcome

The front door tells the loop story: README reorganized around Specify → Execute → Observe → Govern → Learn (the ADR-0034 module→leg table rendered, the two spanners honestly marked), every count true (agents 25, skills 2, commands live), the stale "v2 roadmap: SessionEnd knowledge capture" bullet struck (it shipped), architecture.md's headline inventory fixed. `stats digest` folds into the weekly session-intel file as a "harness scorecard" section (no new daemon). The scheduler ships as ADR-0034 §9 decided: ONE weekly LaunchAgent template + a small dispatcher reading a declarative jobs list (session-intel digest, kit-retro staging; adding a job later = one jobs-list line, never a new plist), one BTM-compliant launcher, one runbook; the existing per-job session-intel plist RETIRES in the same change. Consumer instantiates the one plist (SPEC-126 split; the loading click is Han's). As the final PR it also carries the mega's close-out: RUN_REPORT.md + 2-3 freeze-PNG proofs of the delivered surfaces (learn propose staged diff, the dashboard, config list).

## Quality bar

An external contributor reads the README cold and can say what the five legs are, which module serves which, and what happens to a run's data after it ships. Nothing asserts what a parity grep does not pin (the 11-vs-25 drift died untested once; never again).

## How to close the loop

1. Rewrite README's structure per ADR-0034 §3; mermaid five-leg diagram GitHub-native.
2. Parity greps as committed test lines (extend the existing test-meta pattern) so the counts CANNOT drift silently again; run + capture.
3. Fold digest into session-intel; fixture-generate one intel file; capture the section.
4. Author the ONE scheduler: dispatcher + jobs list + single LaunchAgent template (BTM rules: ProgramArguments[0] = script path, launcher no .sh extension) + runbook; retire the per-job session-intel plist; NC: an unknown jobs-list entry logs + skips, never crashes the week.
5. Mega close-out: RUN_REPORT.md (outcome table, defects caught mid-run, evidence index) + freeze-PNGs, committed on THIS branch so they ride the final PR.

**Done =** parity tests green + README five-leg section rendered (screenshot) + digest-in-intel fixture captured + LaunchAgent template/runbook committed + RUN_REPORT + visual proofs on the branch; PR open and HELD as the gated-final click.

Kit-adopted repo: record gates via `bash lib/gate/gate-ledger.sh` per lane plan before the PR push.

## Handoff on completion

1. Flip ROADMAP box + PR #. 2. Final summary block to NOTES.md ## Event log. 3. DECISIONS.md: anything the rewrite deliberately dropped from the old README. 4. Emit the gated-final banner; the mega closes on Han's merge. EXIT.

## Scope edges

**In:** README/architecture/MANUAL truth + reorganization, digest fold, LaunchAgent template + runbook, mega close-out artifacts, the one-line ID-273 pointer note (kit-retro moved to SG-05) if not already done.
**Out:** PHILOSOPHY.md rewrites (add at most one pointer), new features of any kind, the v2.0.0 tag/release (separate staged item, Han's click).
**Not:** re-documenting every env var in README (that is `config list`'s job now; README points at it), a docs site, translating docs.

## Where to look

ADR-0034 §3 (the table to render), the docs-agent audit in the brief's source notes (the exact stale claims), `lib/session/intel`, `tests/test-meta.sh` (parity-pin pattern), tools/tide deploy/macos (BTM-compliant plist calibration, ops-toolkit).

## PR body

Front door tells the loop: README five-leg reorganization + parity-pinned counts (agents 25, skills 2), digest folded into weekly intel, consumer LaunchAgent prepared, mega RUN_REPORT + visual proofs. FINAL PR of harness-loop, held for Han's gated-final click. Roadmap: `_meta/megagoals/harness-loop/ROADMAP.md` SG-10.

## Notes
