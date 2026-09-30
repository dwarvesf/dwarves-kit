# Implementation notes: spec depth line (delta from the spec)

| # | Kind | Note |
|---|---|---|
| 1 | Premise shift | SPEC-368 and the rid tag moved every cited line. `commands/spec.md`: template `Lane:` now `:86-88`, step 2 `:34-92`, design pass `:302`. `docs/WORKFLOW.md`: every-step table test-plan row `:346`, cycle row `:152`, command row `:1320`. The spec's "always runs" wording no longer exists; the row said only `(static)`, so the row now carries the floor/full wording. |
| 2 | Deviation | `spec-depth.sh` reads a file, but step 2 runs before step 3 creates the spec. Step 1 now writes a header stub (title, `Generated:`, `Status: DRAFT`, `Lane:`, `Depth:`) at `docs/specs/SPEC-NNN-<slug>.md`, and step 3 fills the same file. NNN is picked as step 3 already describes. |
| 3 | Deviation | TASK-3 (validator) and TASK-4 (routing) share one commit. |
| 4 | Addition | `check` also flags `standard` joined with a deeper level (contradiction). The spec did not list it. |
| 5 | Addition | `check` flags a reason with no content words after stop-word removal, not only importance-only reasons. |
| 6 | Choice | `DEPTH_REQUIRED_FROM` is `2026-09-30`, the build date. The spec's own `Generated:` (2026-09-29) predates it, but it carries a Depth line anyway. |
| 7 | Choice | `level` prints `standard` (plus a stderr note) when a Depth line exists but no segment parses. `check` still exits 1 on it. `wants` uses the parsed set only, so a garbage line wants nothing. |
| 8 | Choice | Open-questions body ignores a `## Open questions` heading inside a fenced block. |
| 9 | Coverage gap found | The first negative control on header-only parsing (whole-file read) stayed green because `level` takes the first `Depth:` match. Added the `body-only-depth.md` fixture (Depth only in a body example) so the control goes red. |
| 10 | Not done | AC7 live `/kit:spec` run: not executed (no live interactive spec run inside a build worker). Covered by the static `spec-md-wiring` section, the ledger verb round-trip in a temp log dir, and the spec's dry trace. |
| 11 | Floor-pass record | Plans were supplied inline; `docs/verification/test-plan-review-team.md` describes its seeded plan only in prose. See `docs/verification/spec-depth-line/floor-passes.md`. |
| 12 | Regenerated | `docs/FEATURES.md` changed in 16 rows; the `get-api-docs` row gained the SPEC-372 reference, the other rows are the registry's regeneration output, cause not traced. |
