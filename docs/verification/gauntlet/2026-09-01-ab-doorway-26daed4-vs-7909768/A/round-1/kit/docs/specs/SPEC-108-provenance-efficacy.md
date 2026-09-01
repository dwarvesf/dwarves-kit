# SPEC-108: meta-agent provenance + runtime efficacy metric

Status: VALIDATED
Lane: normal
Type: spec-feature

## Problem

Nothing distinguishes a draft-agent-GENERATED agent from a hand-written one, and nothing
measures whether a generated agent EARNS its slot at runtime. SPEC-088 validates an agent's
DEFINITION at install (structural + effectiveness); there is no signal after that. Two gaps:

1. **Provenance:** the five kit-hardening-generated agents (advisor, brief-reviewer,
   acceptance-verifier, system-verifier, recheck-verifier, all first-committed 2026-07-02)
   carry no marker that they came from the meta-agent, and `commands/draft-agent.md`'s install
   path stamps none, so future generations are equally anonymous.
2. **Runtime efficacy:** SPEC-073's metric set stops at the definition; there is no metric for
   "does a generated agent actually catch real issues once deployed?"

The mega-goal (roadmap: ops-toolkit `_meta/megagoals/kit-face/`, assumptions 05) resolves both.

## Solution

1. **Backfill provenance** on the five generated agents , a frontmatter key
   `generated-by: draft-agent 2026-07-02 <context>`, the `<context>` derived from each agent's
   existing `Source:` footer (not invented). Added after the `model:` line; order-independent for
   the lint.
2. **Emit it going forward** , `commands/draft-agent.md` Step 4 (the install flow, "Write it to
   `agents/<name>.md`") gains an explicit instruction to stamp
   `generated-by: draft-agent <YYYY-MM-DD> <one-line context>` into the frontmatter at install.
   The emit is lead-driven prose (draft-agent.md is a command prompt; install is done by the main
   agent, no shell installer), the same SPEC-078 fidelity 04 used; the FORMAT is pinned against
   the five real carriers so future installs stay consistent.
3. **Metric 11 (runtime efficacy)** , SPEC-073 gains a metric-table row + an `## Amendments`
   entry: "generated-agent catch COUNT" (a count, not a rate , catches-only v1 has no dispatch
   denominator), fed by a LITERAL grep over `docs/verification/*` + spec `## Review` records for
   each generated agent's name (AC2-compliant: the amendment embeds the copy-pasteable command).
   SPEC-088 validates the DEFINITION at install; metric 11 validates the DEPLOYMENT at runtime.
   Distinct from metric 6 (per-lens curve vs per-generated-agent count; same source, different cut).

**Scope honesty (assumption 05).** The "first-N dispatches follow-through" ACTION half is OUT
(nothing records dispatch counts today) , filed to mega NOTES, not silently dropped. Mode C
inline preambles and Mode B sub-goal files carry no frontmatter and are exempt by design. The
additive-marker convention sentence is shared verbatim with SPEC-107's ledger-marker discipline
(one convention, consistent shape).

## Verification

```bash
cd dwarves-kit
# 1. Backfill: each of the 5 generated agents carries a well-formed generated-by (the emit CONTRACT)
for a in advisor brief-reviewer acceptance-verifier system-verifier recheck-verifier; do
  grep -qE '^generated-by: draft-agent [0-9]{4}-[0-9]{2}-[0-9]{2} .+' "agents/$a.md" || echo "MISSING: $a"
done
# 2. Emit FIXTURE (wiring gate, not word-grep): test-meta-agent's install-sim stamps + asserts a
#    well-formed generated-by on a NEW (post-install) agent , proves the install path emits it.
# 3. Set-equality guard: the key set-equals the 5 generated agents (no silent spread), + the
#    negative control that the lint tolerates the key. Both in test-meta.sh.
bash tests/test-meta.sh          # green incl. provenance block (5 format pins + set-equality guard)
bash tests/test-meta-agent.sh    # green incl. the install-sim emit fixture (SPEC-108)
# 4. Emit wiring in the command prose (colon-free <context> rule):
grep -qiE 'generated-by' commands/draft-agent.md
# 5. Metric 11 present with its literal command:
grep -q 'generated-agent catch count' docs/specs/SPEC-073-telemetry-eval-design.md
```

## After state

- `agents/{advisor,brief-reviewer,acceptance-verifier,system-verifier,recheck-verifier}.md` each
  carry `generated-by: draft-agent 2026-07-02 <context>`.
- `commands/draft-agent.md` Step 4 stamps `generated-by:` on install.
- `docs/specs/SPEC-073-telemetry-eval-design.md`: metric-table row 11 + an `## Amendments` entry
  defining metric 11 with its grep command.
- `tests/test-meta.sh`: a provenance block , the 5 agents' generated-by format pin + the negative
  control that the key is tolerated (lint still green). The pin is TARGETED to the 5 generated
  agents (hand-written agents deliberately carry no key).
- `docs/verification/provenance-efficacy.md`: the run-table incl. the CC-load probe.

## Open questions

The probe is a CC-load PROXY: I cannot reload Claude Code's agent registry mid-session, so
"still loads" is proven by (a) the frontmatter remaining valid YAML the same awk parser reads,
and (b) `test-meta.sh`'s frontmatter lint passing with the extra key (no key whitelist,
assumption 05). If a future CC version adds a strict frontmatter key allowlist, the probe becomes
a real reload test; noted. Metric 11 v1 is catches-only by design; the dispatch-count ACTION line
is a filed follow-up, not scope.
