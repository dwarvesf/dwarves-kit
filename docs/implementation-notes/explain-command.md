# Implementation notes , /kit:explain (SPEC-124)

The DELTA from SPEC-124 / ADR-0031 §2. Decisions the spec did not pin down, deviations, and the
constraints that shaped the build. Not a mirror of the spec.

## 2026-07-03 12:00 Lane = normal (not full), by the classifier

Context: the conductor's brief guessed "likely full , new command surface + composes skills".
Decision: lane = **normal**. Why: `lib/lane-classify.sh classify` returns `normal` for every phrasing
of this task (command + lib + tests). `explain.sh` is a NEW feature lib, not one of the enforcement/
telemetry libs (lane-telemetry / mega-merge / proof-ledger / gate-ledger) that escalate to full.
Alternatives: force `full` "to be safe" , rejected as cargo-cult ceremony the classifier does not ask
for (kit-faithful: follow the tool). Impact: fewer required gates (spec/build/ship measure-twice); I
still ran `/kit:review-team`-level scrutiny because the change touches `lib/` (AGENTS.md SPEC-069), and
still wrote the `## Design` block because the work is design-bearing per ADR-0031 §1 (new component).

## 2026-07-03 12:10 Split plane: grounded lib + composing command (the architectural guarantee)

Context: the hard constraint is "ground in the diff, never the agent's narrative". Decision: put ALL
grounding + ordering in `lib/explain.sh`, whose ONLY input is a git ref , there is no argument through
which a narrative could enter. The command (`commands/explain.md`) composes narrate-log + svg-knowledge-
diagram ON TOP of the grounded skeleton. Why: making the constraint STRUCTURAL (no narrative channel)
beats making it a prose promise the LLM might break. Impact: the load-bearing NC (AC4) tests the lib
directly and is deterministic.

## 2026-07-03 12:20 REVERSED after review: the commit subject IS a narrative channel , it leaked

Context: the first cut of the NC (AC4) kept the commit subject NEUTRAL and put the false narrative only in
the commit BODY + an untracked file (channels the engine never reads). I justified this as "proving the
tool has no narrative channel". A fresh-context review (kit:code-reviewer, architecture lens) correctly
called this a hole: the engine DID read the commit subject (`git log -1 --format=%s`) and echoed it as
`# Explainer: <subject>` and `Goal (from the change itself): <subject>` , unverified. A repro confirmed:
subject "add multiply operation" over a diff that adds `subtract` produced an explainer whose Goal said
"multiply". That is exactly the plausible-but-wrong narrative ADR-0031 §2 exists to block, and my NC was
constructed to sidestep the one channel that leaked. The reviewer was right; I waved a real MAJOR the
first time.

Fix (reversed decision): (1) the engine now DERIVES the Goal from the diff (`_change_shape`: adds/modifies/
removes which files), never from the subject; the title is `# Explainer for <ref>` (no subject); the
subject is surfaced ONCE, explicitly labeled "Commit subject (UNVERIFIED author metadata, cross-check
against the diff)". (2) AC4 gains fixture C , the STRONG control , where the commit SUBJECT itself lies
("add multiply") while the diff adds `subtract`; it asserts the Goal is diff-derived, the title is clean,
and every `multiply` occurrence sits on an UNVERIFIED-labeled line (0 trusted leaks). The original body/
untracked-file case is kept as AC4a (it still proves the no-arg-channel guarantee); AC4b is the one that
matters. Lesson: the commit message is the author's narrative; grounding "in the diff" means the code
wins over the message everywhere, including the subject line.

## 2026-07-03 12:25 Three review MINORs fixed (rank anchoring, invalid-ref, mermaid escaping)

Same review pass flagged three minors, all fixed: (1) `_rank`'s test-bucket globs were loose substrings
(`*test-*`, `*spec.*`) that misclassified `latest-value.js` / `aerospec.txt` as tests , anchored to the
basename (`test-*`, `*_test.*`, `*.spec.*`) + path segments (`tests/`, `/spec/`). (2) `_resolve` treated a
typo'd ref as a root commit and, under `set -uo pipefail` (no `-e`), silently emitted an empty "grounded"
explainer , now it `git rev-parse -q --verify`s the head up front and exits 3 with a message (call sites
switched from process-sub to `$(...) || exit 3` so the failure propagates). (3) mermaid node labels built
from raw basenames , a `"` in a filename would break the quoted label , now escaped. None change the
happy-path behavior; they close silent-degradation edges.

## 2026-07-03 12:30 Frozen surfaces: no BLOCKED flag needed

Context: the brief flagged a possible BLOCKED if test-meta demanded the new command be registered in a
frozen surface (`plugin.json` / `marketplace.json`). Finding: neither file enumerates commands , the kit
auto-discovers `commands/*.md` , so a new command needs NO edit there. The companions that test-meta
DOES hard-enforce are non-frozen: `docs/architecture.md` inventory-table row (row-count == live file
count) and the README command summary count + table rows (28 == live). MANUAL.md is the advisory
doc-impact companion. No frozen file was touched; no BLOCKED flag.

## 2026-07-03 12:35 Mermaid default in the lib; svg-knowledge-diagram escalation in the command

Context: ADR-0031 says "a diagram (via svg-knowledge-diagram / mermaid)". Decision: the lib emits a valid
mermaid change-map (grounded in the diff's file/rank structure, GitHub-native per SPEC-113) as the
default, testable diagram; the command layer escalates to an SVG via svg-knowledge-diagram when a
conceptual figure teaches better. Why: keeps a grounded + assertable diagram in the testable plane while
honoring "compose, don't reinvent" (the pedagogy skill is invoked, not forked) at the command layer.
