# Implementation notes -- hard-rule-registry

No spec: the brief fixed the five items. Proof: `docs/verification/hard-rule-registry.md`. These notes record only what the brief left open.

## Decisions

| Decision | Why |
|---|---|
| The registry is `docs/hard-rules.tsv`, one row per rule, seven columns | A TSV needs no parser beyond `cut`, a doc table would need one, and the kit's other registries that tests read (the module registry, FEATURES) are tables only because humans read them first. This one is read by a test first. |
| A row names `enforcer`, a literal `rule` found in that file, a `test`, and a literal `needle` found in that test | A bare path check passes when a rule is deleted and the file stays. The literal pair fails the registry the moment the rule or its proving assertion is renamed or removed. |
| The `gate` column is `always`, `on:<key>`, `off:<key>` or `opt-in:<what>`, checked against `lib/gate/gate-policy.sh` | The risk list says a consumer assumes the HARD labels while four gates default off. The registry now states each rule's default, and the suite fails if a row says `off` for a key the code defaults ON. |
| A doc HARD mark maps to a row through the `doc_terms` column (the hook or rule name on the same line) | The marks live in ASCII diagrams, tables and prose; a same-line term is the only mapping that survives all three. A diagram that split the mark from the name had to be redrawn. |
| The scan reads root `*.md`, `docs/`, `commands/`, `skills/`, `examples/`, `agents/`, minus dated records | The brief names docs, commands, skills and examples. Root files and agents carry marks too (`AGENTS.md`). Specs, verification runs, research, retros, decisions, implementation notes, handoffs, releases, briefs, absorption notes, audits, the changelog and the generated design record say what was true on their day. |
| Two line shapes are definitions, not claims: a line pointing at `docs/hard-rules.tsv`, and `HARD hook:` (the placement test in `docs/architecture.md`, which this slice does not own) | A legend has to be able to say what the label means without naming a rule. |
| The suite carries `# always:` and joins the `test-meta.sh` runner list | A doc edit anywhere can add a bogus mark, and `bin/test-affected` picks meta areas by path. `# always:` runs it on every `--changed` diff for a few hundred milliseconds. |
| The verification pipeline stays one of the "four hard stops" in prose, relabelled "where an autonomous run stops" | It is run by the command text; `ship-gate` checks only that its gate was recorded. Calling it a code-enforced blocker was the false claim. The four-stop doctrine is also in files this slice does not own, so the count stays and the wording says what each stop is. |
| `spec-drift-guard` and the spec-validate design-record lens lose their HARD labels | The hook only warns. Reviewer 6 is prompt text with a blocking verdict, not a hook. |
| Wave converge asks `gh pr view` (through `MEGA_MERGE_GH`) for the PR state | The hook exit code proves nothing: the default hook is a dry run that exits 0. No new env knob: a `WAVE_*` or `QUEUE_*` name must be registered in `lib/config/module-registry.md`, which this slice does not own. A real merge needs a `WAVE_MERGE_CMD` wrapper that passes `--execute`. |
| Converge returns 0 after a dry run and keeps going | Stopping on every dry run would make the default wave path unusable. The truth is in the event (`merge-dry-run`), not the exit code. |
| Queue delta evidence is a HEAD move or a PR created since the window opened (`gh pr list --state all`, filtered by `createdAt`) | A run in a worktree leaves the main checkout's HEAD where it was but opens a PR. Uncommitted edits do not count: the breaker credits them as progress, but a `done` row means shipped work. A missing `gh` leaves only the HEAD check. |
| The rule covers `RUNNER_DONE` as well as `EXIT_SIGNAL: true` | Both are a run's own claim. The brief's "a row reaches done only when" is general. |
| The reaper journals a finished-but-orphaned run `gated`, never `done` | The reaper does not know the slug's repo, so it cannot check the delta. A run that wrote its own `REASON` keeps that reason. |
| The test fixture mux commits on window open when `<slug>.work` exists | The queue suites asserted `done` on a pane marker alone. They now say how the run "worked", and a no-work twin of each shape asserts `gated no-delta`. |

## Deviations from the brief

None. Edits the brief fenced to other slices are listed in the PR as "Needs from others".
