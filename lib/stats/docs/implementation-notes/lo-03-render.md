# Implementation notes lo-03-render (delta from sub-goal spec)

Sub-goal: `_meta/megagoals/ledger-observatory/goals/03-render-skill.md`.

## Status

In progress (headless build worker, kill-resilient commits at each phase boundary).

## Deviations from the goal file / ROADMAP

- **Lane-classify returned `tiny`; treated as `normal`.** `lane-classify.sh classify`
  on the sub-goal description returned `tiny`, but the goal file's own "How to close
  the loop" explicitly mandates `/spec` + `/spec-validate` before code, plus a
  run-table of 5 test scenarios including a negative control. That is normal-lane
  ceremony, not tiny. Per AGENTS.md ("when in doubt between two lanes, take the
  heavier one") and per the goal file being the IMMUTABLE contract, followed the
  goal file's explicit procedure over the classifier's default. Recorded as a
  gate-ledger `action` note.
- **SPEC co-located at `tools/ledger-observatory/docs/specs/SPEC-128-render-skill.md`**,
  continuing the tool's own local SPEC-number sequence (126=schema, 127=etl-cli),
  per `_meta/README.md` "SPEC numbers are per-namespace local."
- **PR base is `main`, not `feat/lo-02-etl-cli`** as the goal file's header states.
  The goal file was authored while 02 was still in flight (stacked-PR plan); 02 has
  since merged to `main` (PR #673, e6ff875b), so the stack collapsed and `main` now
  carries everything 03 depends on. The headless-worker dispatch instructions
  (worker-03.txt) confirm this explicitly ("Sub-goals 01+02 are MERGED to main...
  open a PR to base main"), so basing on `main` is the correct current target, not
  a deviation from intent, just from the goal file's stale header.
- **Per-feature proof doc lands as a DIRECTORY, `docs/verification/render-skill/`, not a
  flat `.md` file** like SG-01/02's `verification/schema.md` / `verification/etl-cli.md`.
  worker-03.txt's dispatch instructions say "per-feature design/log under
  `docs/verification/render-skill/`" (trailing slash) verbatim, and SPEC-016's own stated
  shape (`CLAUDE.md` "Done gate") is "per-feature designs/logs under
  `tools/<name>/docs/verification/<feature>/`" , also a directory. The flat-file sibling
  precedent (SG-01/02) predates that literal instruction; kept the DIRECTORY shape since it
  is both what was asked and matches the canonical rule, and it is also what the captured
  samples (`samples/terminal-sample.txt`, `samples/artifact-sample.html`) needed to nest
  under anyway. The doc inside is `render-skill/render-skill.md` (mirrors the directory
  name); `proof-of-done.md`'s index links to that nested path.
- **Single continuous implementer, not a per-task subagent dispatch** for `/kit:execute`.
  `lane-classify.sh` returned `tiny` for this sub-goal (see the first bullet above); given
  the small single-tool scope (7 tasks, one new module, one new CLI subcommand, one skill
  file), implemented directly rather than spinning up a worker-per-task + task-verifier
  chain. Verification discipline was kept (real test runs after each unit, a deliberate
  negative-control break-and-restore, regression checks against SG-01/02's existing
  suites) rather than skipped; only the AGENT-DISPATCH mechanics were simplified.

## 2026-07-03 20:28 Self-review caught an unparseable SKILL.md frontmatter

- Context: `skill/SKILL.md`'s first-draft `description:` value contained two unquoted
  colons inside the plain YAML scalar (`"...bot-reply-formatting: tables..."` and
  `"READ-ONLY by hard contract: the CLI..."`). All grep-based `R-trigger` test cases
  passed anyway (they only check substring presence).
- Decision/Change: rewrote both occurrences to the repo's existing " , " separator
  style; added a new `R-trigger frontmatter parses as valid YAML` case to
  `tests/test-render-skill.sh` (invokes `python3 -c "import yaml; yaml.safe_load(...)"`
  against the actual frontmatter block) so this class of defect fails loudly in future.
- Why: a skill whose frontmatter does not parse as YAML cannot load in Claude Code at
  all , this is a silent, total failure mode the grep checks structurally cannot see
  (they test string content, not document validity).
- Alternatives considered: leaving it grep-only (rejected , exactly the gap that let
  the bug through); double-quoting the whole value instead of removing the colons
  (rejected , would require escaping every one of the ~10 embedded double-quoted
  trigger phrases, more fragile than just not using a bare colon in prose).
- Impact: test count 29 -> 30; the multi-feature proof doc + README samples updated to
  the corrected count/timestamp; no other file affected.
