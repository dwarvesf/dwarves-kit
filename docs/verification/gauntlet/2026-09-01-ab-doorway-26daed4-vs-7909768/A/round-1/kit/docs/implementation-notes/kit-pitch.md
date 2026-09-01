# Implementation notes: kit-pitch (SPEC-140)

Delta from the spec only; see `docs/specs/SPEC-140-kit-pitch.md` for the full design and its
own `## Decision Log` (DEC-001/002/003, pinned before build). This file covers what came up
DURING implementation the spec did not (or could not) anticipate.

## 2026-07-04 08:35 unsanitized `<rid>` in filesystem globs (self spec-validate finding)

**Decision:** added `_safe_slug()`, a one-line guard rejecting any slug containing `/`, `\`,
or `..`, called at the top of `_find_spec`/`_find_proof`/`_find_impl_notes` before any glob or
path is built from it.

**Why:** the self spec-validate pass (Reviewer 1, Security Auditor) flagged that `lib/pitch.sh`
builds filesystem paths directly from its `<rid>` argument (`docs/specs/SPEC-*-"$slug".md`,
`docs/verification/$slug.md`, `docs/implementation-notes/$slug.md`) with no sanitization,
unlike `lib/gate/gate-ledger.sh`'s own `ledger_file()`, which already strips `/` via `runid()`
before ever touching disk. A crafted `<rid>` (e.g. containing `../`) could walk a lookup
outside the intended `docs/` subtree. Real rids never contain `/` or `..` (they are branch
slugs with the `type/` prefix already stripped, SPEC-070), so the guard costs nothing on the
happy path and closes the read-only path-traversal read risk on the abuse path.

**Impact:** none outside `lib/pitch.sh`'s three lookup functions; no test regression (the
fixtures all use plain slugs). Not spec-worthy on its own (a one-line defensive guard, not a
design decision), but recorded here per the self-review that caught it.

## 2026-07-04 08:50 Outcome section: `head -N` truncation cut mid-list, switched to first-paragraph extraction

**Decision:** `cmd_outcome`'s Solution/Problem extraction changed from "delete blank lines,
take the first N lines" to `_first_para()`: print the section's first CONTIGUOUS non-blank
block, stopping at the first blank line reached after at least one line has printed.

**Why:** running the real-sample render against `kit-emit-sweep` (AC1) surfaced the bug
live: SPEC-139's `## Solution` opens with one sentence, a blank line, then a numbered list.
The original `sed '/^[[:space:]]*$/d' | head -8` deleted the blank line (destroying the
paragraph boundary) and then truncated 8 lines later, mid-list-item ("...`design.md` -> `Design`
(a real matrix row, "Design (opt-in)")" cut off with no closing context). A one-paragraph
outcome must not end mid-sentence. `_first_para` fixed it structurally: it now stops at the
genuine paragraph boundary (the first real blank line), so a numbered-list Solution (common in
this kit's own specs) yields just its lead sentence, never a ragged mid-list cut.

**Impact:** none outside `cmd_outcome`/`cmd_cost`'s Out-of-Scope block (which uses a different,
already-line-based extraction and was unaffected). Caught by actually running the real-sample
proof, not by reading the design on paper -- the same "run it before trusting it" lesson
`kit-emit-sweep`'s own implementation-notes recorded for its parser.

## 2026-07-04 09:05 the never-auto-post test almost re-triggered the self-referential fixture trap

**Decision:** the AC5 negative control checks `lib/pitch.sh`'s non-comment lines and
`commands/pitch.md`'s fenced ` ```bash ` code blocks ONLY, not the whole file.

**Why:** the first draft grepped the whole file for `gh pr comment|gh issue comment|discord|
slack|curl` and failed with 5 hits, all of them the BOUNDARY-DOCUMENTING prose itself (`lib/
pitch.sh`'s header comment and `commands/pitch.md`'s "Rules"/"Step 2" text both legitimately
say "never shells out to `gh pr comment`..."). This is the exact self-referential
fixture/scanner trap `kit-emit-sweep`'s own implementation-notes already named ("this file has
no secrets" trips a scanner on the word "secrets"). The fix narrows the check to what an agent
or the shell would actually EXECUTE: `lib/pitch.sh`'s lines minus `#`-comments, and only the
fenced bash blocks in `commands/pitch.md` (the two `bash lib/pitch.sh render ...` / `bash
lib/gate/gate-ledger.sh record ...` calls) -- both come back clean (0 hits), and the prose mentions
are asserted SEPARATELY as a "documents it never posts" check instead of being folded into the
same forbidden-pattern grep.

**Impact:** none outside `tests/test-pitch.sh`; a test-design fix, not a product-code change.

## 2026-07-04 15:20 AC1's two ledger-content checks moved off live machine state onto a frozen fixture (CI fix)

**Decision:** AC1's structural checks (file written, 5 sections present, spec name) still assert
against the live render (`bash lib/pitch.sh render kit-emit-sweep --out
docs/verification/pitch-command/sample-pitch.md`, unchanged). The two checks that need ledger
content -- the PR link and the grill-skip reason -- now assert against a NEW render of a frozen,
committed fixture rid (`tests/fixtures/pitch/real-sample/`, via a new `_render_with_origin`
helper) instead of that live output.

**Why:** CI runs from a fresh checkout with no `~/.local/state/dwarves-kit/logs/runs/
kit-emit-sweep.log` (that ledger only exists on a dev machine that already ran/shipped this rid,
per `lib/telemetry/kit-log-dir.sh`'s XDG-state default). The live render's spec/proof/implementation-notes
lookups all resolve fine in CI (those ARE committed files), but `_ledger_pr`/`_ledger_grill`
read from the machine-local ledger and come back empty, so the PR-link and grill-reason checks
failed 27/29 in CI while passing 29/29 on a dev machine (confirmed by reproducing the exact 2
failures locally with a scrubbed `HOME`, then confirming they clear once the checks target the
fixture). `_render_with_origin` also `git init`s the scratch workspace and sets `origin` to the
real `dwarvesf/dwarves-kit` remote (local config only, no network) so `_pr_url` resolves the
same `.../pull/168` shape the live render would produce with a real git remote, rather than
loosening the assertion to accept the bare `#168` fallback.

**Impact:** none outside `tests/test-pitch.sh` and the new `tests/fixtures/pitch/real-sample/`
fixture files; `lib/pitch.sh`, `commands/pitch.md`, and every other AC are untouched. The
human-facing `docs/verification/pitch-command/sample-pitch.md` artifact keeps being regenerated
against the live `kit-emit-sweep` rid on every local run (still genuinely real evidence on a
machine that has the ledger); it is simply no longer a CI-verified input.
