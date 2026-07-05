# Proof of done: operate-contract refresh (kit-modularity SG-05)

Refresh `AGENTS.md` + `WORKFLOW.md` (the operate-contract an adopting agent reads
first) to the post-modularity surface: standalone `<subsystem> <verb>` commands,
`stats` (not `ledger-observatory`), the layered `install.sh --with` model + the
per-consumer `kit.toml [modules]` manifest, and self-contained subsystem modules
(the retired lib-vs-tools framing). Docs-only, load-bearing (rung 2).

## Acceptance criteria

| # | Criterion | Status |
|---|---|---|
| AC1 | No retired-surface token survives as a LIVE reference in either file: `ledger-observatory`, `bash tools/`, `tools/<x>/` invocation paths, an all-hooks / "wires everything by default" install description, a lib-vs-tools split framing | PASS |
| AC2 | The new surface is positively referenced in BOTH files: `stats`, `<subsystem> <verb>`, `install.sh --with`, `kit.toml [modules]`, subsystem modules | PASS |
| AC3 | Every `lib/<subsystem>/*.sh` path referenced in either file resolves on disk (no dangling path from the SG-01 restructure) | PASS |
| AC4 | `kit:doc-verifier` finds zero contradictions between the two files and the live codebase | PASS |
| AC5 | Surgical: lane/gate semantics unchanged; only additive composition notes + the already-swept paths | PASS |

## Implementation

The SG-01..04 merges (call-site sweep for the alias removal, the `stats` rename,
the `tools/` fold) had ALREADY updated every `lib/...sh` path reference and removed
every retired token from both files as a side effect. So AC1/AC3 were satisfied on
arrival (confirmed, not assumed, by the audit below). The SG-05 delta is AC2: neither
file POSITIVELY described the new composable surface. Added one concise composition
note to each:

- `AGENTS.md`: new appendix `## How the kit composes (subsystem modules)` after zone 4,
  before `## How a goal is composed`. Names the subsystem-module structure, the standalone
  `<subsystem> <verb>` commands (additive over the internal path form), the `stats` read
  plane, the no-uber-dispatcher rule, and the layered `install.sh --with` + `kit.toml [modules]`
  adoption model, pointing to PHILOSOPHY/README for the full model.
- `WORKFLOW.md`: new section `## Subsystem modules and install layering` right after
  `## Required reading`. The WORKFLOW-relevant slice of the same surface, pointing back to
  the AGENTS.md appendix for the full composition note (no duplication of the adoption model).

No lane, gate, phase, or state-machine text was touched.

## Confirmation run-table

| # | Check | Command | Result |
|---|---|---|---|
| 1 | AC1 retired tokens (green run) | `grep -nE 'ledger-observatory\|bash tools/\|tools/[a-z]\|all-hooks install\|wires everything' AGENTS.md WORKFLOW.md` | no matches (clean) |
| 2 | AC1 per-token counts | `grep -cE '<tok>' AGENTS.md WORKFLOW.md` | ledger-observatory 0 / bash tools/ 0 / tools/[a-z] 0 / all-hooks install 0 / wires everything 0 |
| 3 | AC2 new tokens (both files) | `grep -c '<tok>' AGENTS.md WORKFLOW.md` | stats A3/W2 · `<subsystem> <verb>` A1/W1 · `--with` A1/W1 · `[modules]` A1/W1 · subsystem-module A2/W1 · kit.toml A1/W1 |
| 4 | AC3 path existence | `[ -e lib/<sub>/<file>.sh ]` over all 19 referenced paths | all 19 exist |
| 5 | AC4 doc-verifier | `kit:doc-verifier` agent over both files vs codebase | PASS, 0 contradictions |

### Negative control

The NC is the AC1 audit itself: a grep for each retired token across both files
returns ZERO live references (check #1/#2 above, empty output). This distinguishes
a real refresh from a cosmetic one, if a retired name had survived as a live
instruction, the grep would surface it. All five retired-token classes return 0.
Positive control (AC2, check #3): the new tokens ARE present in both files, so the
zero is genuine absence of the OLD surface, not an empty file.

### Reproduce

```
cd <worktree>
grep -nE 'ledger-observatory|bash tools/|tools/[a-z]|all-hooks install|wires everything' AGENTS.md WORKFLOW.md   # -> no output
for t in stats '<subsystem> <verb>' '--with' '[modules]' 'subsystem module' 'kit.toml'; do echo "$t: A=$(grep -c -e "$t" AGENTS.md) W=$(grep -c -e "$t" WORKFLOW.md)"; done
for f in $(grep -ohE 'lib/[A-Za-z0-9_./-]+\.sh' AGENTS.md WORKFLOW.md | sort -u); do [ -e "$f" ] && echo "OK $f" || echo "MISSING $f"; done
```
