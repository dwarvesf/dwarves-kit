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
unlike `lib/gate-ledger.sh`'s own `ledger_file()`, which already strips `/` via `runid()`
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
lib/gate-ledger.sh record ...` calls) -- both come back clean (0 hits), and the prose mentions
are asserted SEPARATELY as a "documents it never posts" check instead of being folded into the
same forbidden-pattern grep.

**Impact:** none outside `tests/test-pitch.sh`; a test-design fix, not a product-code change.
