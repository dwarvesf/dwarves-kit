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
| **C5 Currency** | Every proposer emits `## [staged]` blocks through `lib/learn/staging-format.py` and never writes a board directly. The human gate (`board promote`) owns that write. | Three proposal shapes for one gate. `session-audit triage` invented a fourth before review caught it. `session intel` (T6) and `/kit:retro` (T7) emitted prose nobody could promote until 2026-07-15; every proposer now speaks the one currency. |
| **C6 Durable root** | Anything that persists resolves its path through `lib/telemetry/kit-log-dir.sh` (SPEC-097). Never hardcode `~/.claude/dwarves-kit/logs`. | `queue.sh` defaulted its journal into the exact path a plugin reinstall wipes: the one telemetry corpus SPEC-097 did not protect. |
| **C7 Portable tests** | No test invokes a tool CI lacks (`rg`, `fd`, `sd`, `bat`...). Use POSIX `grep`/`find`. | The C1 lint's first cut used `rg`. On CI, `rg` is absent, the sweep produced no output, and the emptiness-assert **passed vacuously**. Only its negative control caught it. |

## What the lint does NOT check (do not mistake green for safe)

Stated plainly, because a contract that over-claims is worse than one that admits its edges:

- **C1** checks env-var *references* and *executable names*. It does not check TOML keys,
  function names, directory names, or a name inside a string that is later `eval`'d.
- **C2** checks that a tool's basename is *mentioned* in an operator surface. A comment
  mentioning it satisfies the grep as well as a real dispatch does.
- **C3/C4** check that artifacts *exist*. They cannot tell a real README from a stub, and
  known pre-existing gaps live in `tests/kit-contract-known-gaps.txt` (visible IOUs, and the
  lint fails on any gap NOT listed there, so no new debt can land).
- **C5** catches the renderer bypass and three board-append shapes; a `sed -i` insertion or a
  path assembled at runtime evades the grep. The real guarantee is the shared renderer.
- **C6** is a literal-path match; string concatenation evades it.

This is why the lint is only half the gate. The other half is the review lenses (below), and
they are not optional for a new module.

## The rule behind the rules: every absence-assertion needs a planted violation

Five of the seven rules assert that something is *absent* (no `CC_*`, no bespoke block, no
hardcoded path, no non-portable tool). An absence-assertion that cannot fail is worse than
no test: it reports safety it never checked. So `tests/test-kit-contract.sh` plants a
violation for each and asserts it is caught.

And the planted violation must arrive in a shape the rule's author did NOT have in mind. A
negative control that plants the violation in the exact syntactic form the regex was written
against proves only that the regex matches itself.

This is not theory. In one afternoon the discipline caught, in this order: the `rg`-on-CI
vacuous pass; a lint that flagged its own fixture; C1 blind to `os.environ.get('X')` in single
quotes, to `os.environ["X"]`, and to a bare `export X=`; C6 blind to every extensionless
executable (which is the kit's own house style, so it was blind to most of the kit); C7 blind
to `rg "pat" file` with no flag; C5 fooled by a bespoke writer that name-dropped the renderer
in a comment; and a module-scope definition under which C3/C4 examined 3 of the kit's 12
modules while reporting green. Every one of those was found by a review lens re-planting the
violation differently, not by the suite itself.

## Fanning work out to parallel agents

**One worktree per writer. No exceptions, and this one is not theoretical.**

On 2026-07-15 three agents were dispatched into the SAME checkout to close three doc gaps in
parallel. Git branches share a working tree, so within minutes: HEAD had been switched out from
under two of them, one agent's commit landed on another's branch, the contract test flapped red
from a half-built scaffold that was not its own, and `git .../index.lock` collisions appeared in
the session's own telemetry. Both agents detected the collision and untangled it with plumbing
(`commit-tree`, an atomic ref update) without destroying anything, but that recovery was luck
plus care, not design.

- Dispatch with `Agent(isolation: "worktree")`, or hand each agent an explicit `cwd` in a
  worktree the lead created first. A subagent must never create its own.
- Read-only fan-out (Explore, reviewers, research) needs no worktree: it writes nothing.
- The lead merges, one branch at a time. Two writers, one index, is a corruption waiting for a
  timing coincidence.

If you catch yourself thinking "they are touching different files so it is fine": they are not
touching different HEADs.

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
