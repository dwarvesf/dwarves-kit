# The kit contract

What every module, tool, and skill in this kit must satisfy. Not style preference: each
rule below exists because its violation already shipped and cost something. The citation
in each row is the incident, not a hypothetical.

**These rules are executable.** `tests/test-kit-contract.sh` is this page as a lint. If you
are reading this to decide whether your change is compliant, run the lint instead; if the
lint and this page ever disagree, the lint wins and this page is the bug.

## The seven rules

| # | Rule | Why (the incident) |
|---|---|---|
| **C1 Naming** | No kit-owned name carries the host-agent prefix (`cc-`, `CC_*`). A module owns a prefix (`STATS_*`, `SESSION_*`, `QUEUE_*`, `SKILL_CURATOR_*`). A name the HOST provides (`CC_PLUGINS_DIR`) keeps the host's spelling: we read it, we do not own it. | The prefix was retired once by hand, then `lib/stats` entered the kit and reintroduced `CC_BACKLOG_*` for the identical two files, while `CC_SI_*` (220 occurrences) survived untouched. Renamed-once-not-everywhere is a lint's job. |
| **C2 Wiring** | Every module executable is reachable from an operator surface: a `bin/` entry or a `lib/<mod>/<mod>.sh` dispatcher case. A tool nobody can invoke is a tool nobody runs. | `session-audit` shipped with tests, docs and a proof, and no dispatcher case: the advertised `session audit run` did not resolve. `plugin-check` lived only at its deep lib path for 9 days. |
| **C3 Docs** | Every module has `README.md`, a spec (`SPEC.md` or `docs/specs/SPEC-NNN-*.md`), and `docs/proof-of-done.md`. | `plugin-check` had a 27-assertion suite and no proof-of-done, so the kit's own done-gate had nothing to read. The evidence existed; the artifact did not. |
| **C4 Tests** | Every module has at least one `tests/*.sh`. | Baseline. A module with no test is a claim with no evidence. |
| **C5 Currency** | Every proposer emits `## [staged]` blocks through `lib/learn/staging-format.py` and never writes a board directly. The human gate (`board promote`) owns that write. | Three proposal shapes for one gate. `session-audit triage` invented a fourth before review caught it; `session intel` and `/kit:retro` still emit prose nobody can promote. |
| **C6 Durable root** | Anything that persists resolves its path through `lib/telemetry/kit-log-dir.sh` (SPEC-097). Never hardcode `~/.claude/dwarves-kit/logs`. | `queue.sh` defaulted its journal into the exact path a plugin reinstall wipes: the one telemetry corpus SPEC-097 did not protect. |
| **C7 Portable tests** | No test invokes a tool CI lacks (`rg`, `fd`, `sd`, `bat`...). Use POSIX `grep`/`find`. | The C1 lint's first cut used `rg`. On CI, `rg` is absent, the sweep produced no output, and the emptiness-assert **passed vacuously**. Only its negative control caught it. |

## The rule behind the rules: every absence-assertion needs a planted violation

Five of the seven rules assert that something is *absent* (no `CC_*`, no bespoke block, no
hardcoded path, no non-portable tool). An absence-assertion that cannot fail is worse than
no test: it reports safety it never checked. So `tests/test-kit-contract.sh` plants a
violation for each and asserts it is caught.

This is not theory. In one afternoon it caught two vacuous passes (the `rg`-on-CI bug, and
a lint that flagged its own fixture). Both would have shipped as green.

## Adding a new module, tool, or skill

Work the list, in this order. Every step has a check you can run.

1. **Name it by function, not by host.** Module dir `lib/<name>/`, env family `<NAME>_*`, executable named for what it does. Check: `bash tests/test-kit-contract.sh` (C1).
2. **Place it on the loop.** Which of the five legs (Specify / Execute / Observe / Govern / Learn, ADR-0034) does it serve? Add the row to `lib/config/module-registry.md`. A tool that fits no leg is a tool with no reason to be in the kit.
3. **Wire it before you polish it.** A `bin/` shim or a dispatcher case, in the SAME commit as the first working version. Check: C2.
4. **Pick the verbs from the closed vocabulary** (SPEC-200 I4): `run` (do the job, write the artifact), `show` (print, write nothing), `propose` (stage proposals), `promote` (the human gate), `trace` (one run's story). Do not invent a synonym.
5. **If it proposes anything, use the currency.** `## [staged]` blocks via `staging-format.py`, deduped against staging + board, promoted by a human. Never write a board. Check: C5.
6. **If it persists anything, use the root.** `kit_resolve_log_dir`. Check: C6.
7. **Docs + proof + tests ride in the same PR.** README, spec, `docs/proof-of-done.md` with a run-table and at least one negative control, `tests/*.sh`. Check: C3, C4.
8. **Run the contract before the PR.** `bash tests/test-kit-contract.sh`. It is the same lint CI runs; failing it locally costs a minute, failing it on CI costs a round trip.

## Where this sits in the harness loop

The contract is a **Govern**-leg gate, and it fires at two boundaries:

- **Execute -> Govern**: `tests/test-kit-contract.sh` runs in CI on every PR. Mechanical rules only (naming, wiring, docs presence, currency, root, portability). It cannot judge whether the docs are any *good*.
- **Govern (judgment)**: for that, dispatch the review lenses. `kit:advisor` (the cross-cutting lens) plus a domain reviewer, and for a new module `kit:agent-effectiveness` if it ships an agent. A lint proves the shape; a reviewer proves the substance. Run both; the lint is cheap and the reviewer is not fooled by a technically-compliant README.

Neither replaces the other. The 2026-07-14 sweep found 19 pipelines that all passed CI and
still fragmented the kit into five vocabularies, because nothing mechanical was watching the
shape and no human was watching the whole.
