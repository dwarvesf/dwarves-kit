# SPEC-107: cheap-tier defaults (three surfaces, one stance)

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

The kit's cheap-first routing stance (SPEC-087: "Opus dominated measured spend; the biggest
$ lever is Opus only on the hard sub-goals") is stated in prose but is NOT the default on the
three AUTHORING surfaces that decide a worker/sub-goal tier, and they disagree:

1. **`commands/execute.md` worker dispatch (2b)** names no per-worker model, so task workers
   INHERIT the session tier. A run started on opus dispatches every worker on opus , the exact
   opus-for-everything cost SPEC-087 warns against.
2. **The `plan-for-mega-goal` subgoal-template** (dotfiles) offers `Model: <haiku | sonnet |
   opus, or OMIT ... to inherit>` , the placeholder shape makes "inherit" the path of least
   resistance, not the cheap default.
3. **`agents/meta-agent.md` Mode B** abstains to OMIT (inherit) and records "a human-set
   default of `sonnet` ... is the safe fallback, but that is the human's call, not a silent
   auto-write" , the opposite of a cheap default.

Result: no single stance. The mega-goal (roadmap: ops-toolkit `_meta/megagoals/kit-face/`)
resolves this to `sonnet` default across all three (ROADMAP `## Assumptions` 04).

## Solution

One stance , `sonnet` is the default worker/sub-goal tier; `opus` is the explicit
hard-reasoning escape hatch , expressed consistently on all three AUTHORING surfaces:

1. **execute.md 2b:** workers dispatch at `sonnet` by default. The active spec's optional bare
   `Model:` header is the hard-reasoning escape hatch: a spec carrying `Model: opus` dispatches
   its workers on opus; absent, workers dispatch sonnet. Verifiers keep their own frontmatter
   tiers (unchanged). A fable-tier session STILL dispatches workers at sonnet , the cheap-first
   default is a stated policy that applies regardless of session tier, not a silent down-tier
   (consistent with SPEC-078's "an explicit tier override is intentional"). If the dispatch
   surface cannot pass a model override, omit it and note that (the SPEC-078 / review-team
   graceful-degrade clause).
2. **dotfiles subgoal-template:** the `Model:` placeholder defaults to `sonnet` (bare line),
   with OMIT documented as a DELIBERATE "inherit the parent tier" choice, not the default.
3. **meta-agent Mode B:** on ABSTAIN, write `Model: sonnet` (the safe cheap default) instead of
   OMITting. OMIT stays documented as the explicit "deliberate inherit" option; the abstain path
   no longer leaves the field to chance. The two old contradiction lines (`-> OMIT the Model:
   line` and "that is the human's call, not a silent auto-write") are rewritten, not merely
   supplemented.

**Write-time default, read-time honored (the honest scope of "one stance").** The sonnet
default is applied at AUTHORING time: surfaces 2+3 bake `Model: sonnet` INTO each goal file.
The existing dispatch reader `_route()` (lib/queue/orchestrate.sh:396-403) then reads that explicit
line and dispatches `--model sonnet` , this is the genuine "default applied at dispatch" (proven
by the existing test-orchestrate fixture, below), NOT a re-encoded rule in a test. `_route()`
itself is UNCHANGED: its absent->inherit fallback is exactly the "deliberate OMIT = inherit"
path assumption 04 preserves. So "one stance" means the three authoring surfaces agree on
`sonnet`; it does not claim `_route`'s omit-fallback was changed (it was not). No `lib/`/`hooks/`
edit , `normal` lane.

## Verification

```bash
cd dwarves-kit
# Surface 1 (execute.md): sonnet default + spec Model escape hatch stated
grep -qiE 'workers dispatch (at )?sonnet by default|default(s)? (to )?sonnet' commands/execute.md
grep -qiE 'Model:.*(escape hatch|hard[- ]reasoning|override)' commands/execute.md
# Surface 3 (meta-agent Mode B): sonnet-on-abstain written; old contradiction GONE (negative control)
grep -qiE 'write .*Model: sonnet|sonnet-on-abstain' agents/meta-agent.md
! grep -qF "human's call, not a silent auto-write" agents/meta-agent.md
! grep -qE '->[[:space:]]*OMIT the .?Model:.? line' agents/meta-agent.md
# Positive default APPLIED AT DISPATCH via the real reader (a goal file carrying the
# template-default Model: sonnet is dispatched --model sonnet); + the opus/inherit cases:
bash tests/test-orchestrate.sh   # incl. :187-206 mixed-tier fixture (Model: sonnet -> dispatch sonnet)
bash tests/test-meta.sh          # green incl. the new tier-defaults surface block; frontmatter lint still green
bash tests/test-meta-agent.sh    # Mode B stance rewrite does not break the meta-agent suite

# Surface 2 (dotfiles half, LOCAL proof only , path absent in kit CI):
grep -qE '^Model: sonnet' ~/workspace/tieubao/dotfiles/home/dot_claude/skills/plan-for-mega-goal/references/subgoal-template.md
```

## After state

- `commands/execute.md` 2b states workers dispatch sonnet by default + the spec `Model:` escape
  hatch + the fable-session clause.
- `agents/meta-agent.md` Mode B writes `Model: sonnet` on abstain; the two old contradiction
  lines are rewritten; OMIT documented as deliberate inherit.
- The dotfiles `plan-for-mega-goal` subgoal-template defaults `Model: sonnet` (applied via
  `chezmoi apply`, staged+committed atomically per the S-64 watcher rule).
- `tests/test-meta.sh` carries a tier-defaults block: surface-1 + surface-3 greps + the
  surface-3 negative control (no residual contradiction text).
- `docs/verification/tier-defaults.md` carries the run-table, incl. the test-orchestrate
  dispatch proof and the local dotfiles diff.

## Open questions

The "default applied at dispatch" is real for the goal-file path (`_route` reads the
template-written `Model: sonnet`), and lead-driven for the execute.md worker path (execute.md is
a prompt; the Task-tool worker dispatch has no shell reader , the sonnet default is instruction
prose, grep-pinned, the accepted SPEC-078 fidelity, test-meta.sh:2266 precedent). No `lib/`
helper is added: a machine-enforced worker-tier reader would escalate to `full` lane and
duplicate `_route`'s `^Model:` extraction; filed to mega NOTES if lead-driven prose ever proves
insufficient.
