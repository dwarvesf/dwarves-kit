# Implementation notes: SPEC-196 staging drain (delta from spec only)

## 2026-07-12 05:00 Shared `staging-format*` landed here (SG-05 had not landed it)

Context: the goal file's shared-fixture rule says whichever of SG-05/SG-06 merges first
lands `lib/learn/staging-format*` (one definition of the `## [staged]`/`## [expired]`
block edges); the other consumes it. `find lib/learn` at the start of this run showed
only `learn.sh` + `weekend-batch.sh` -- no `staging-format*` on this branch's history.
Decision: SG-06 lands `lib/learn/staging-format.py`.
Why: the goal file's own rule; nothing to consume.
Impact: SG-05 (`learn propose`, SPEC-195) should import this module rather than write a
second parser when it lands.

## 2026-07-12 05:05 `staging-format.py` is hyphenated Python, loaded via `importlib`

Context: both goal files' file-fence token is literally `staging-format*` (hyphen), but
`import staging_format` cannot see a hyphenated filename.
Decision: keep the hyphenated name (matches the fence token exactly, and matches
`hooks/backlog-stage.py` / hyphen-friendly precedent elsewhere in `lib/`); `drain.py`
loads it via `importlib.util.spec_from_file_location`, not a plain `import`.
Why: literal fence-token match beats a cosmetic filename change; `importlib` loading a
sibling file by path is a two-line, stdlib-only idiom, not a new dependency.
Alternatives: name it `staging_format.py` (breaks the fence-token match with SG-05's
goal file, risking two divergent shared-fixture files if SG-05 merges expecting the
hyphenated name); `exec()` the file inline (uglier, no real benefit over `importlib`).

## 2026-07-12 05:10 `lib/board/bin/add-backlog` needed NO index-skip change

Context: the goal file asks for "add-backlog's promote/reject numbering skips expired
rows" and gates touching `add-backlog` behind "only if needed."
Decision: did not touch it.
Why: `add-backlog`'s existing `staged = [b for b in blocks if b["state"] == "staged"]`
already filters to `state == "staged"` before numbering; relabeling a block's header to
`[expired]` makes it fail that filter automatically. Verified directly (test-learn-
drain.sh AC6a/AC6b, plus a live run against the real 69-candidate copy).
Impact: zero risk of touching a file SG-05 might also need to edit for its own reasons;
the file stays fully outside this PR's diff.

## 2026-07-12 05:15 Real `flock(1)` not used; `fcntl.flock` (Python) instead

Context: the goal file says "flock-guarded like harvest post-#226." `hooks/harvest.py`'s
post-#226 fix uses Python's `fcntl.flock`, not the bash `flock(1)` binary; a repo-wide
grep confirms bash `flock(1)` has zero usage anywhere in this codebase (macOS ships no
`flock(1)`; `lib/queue/orchestrate.sh`'s own comment says so and uses a `mkdir`-based
lock instead for its bash-side mutual exclusion).
Decision: `drain.py` reuses harvest.py's exact idiom -- a sibling `<staging>.lock` file,
blocking exclusive `fcntl.flock`, acquire/mutate/release in try/finally -- since drain.py
is already Python (the staging-file grammar is Python elsewhere in this repo: backlog-
stage.py writes it, add-backlog reads it). Not the bash `mkdir`-lock idiom, because
drain's write path never leaves Python.
Why: "flock-guarded like harvest" names the harvest.py idiom specifically, and that
idiom IS `fcntl.flock`, not literal `flock(1)`.
Impact: none outside `drain.py`; the lock file is a `.lock` sibling of the staging file,
same convention as `<ledger>.lock`.

## 2026-07-12 05:20 `learn.sh` and `tests/test-bin-forwarders.sh` edited despite not
matching the `drain*`/`staging-format*` file-fence glob

Context: the goal file's own text says the SPEC-196 job is to replace the `learn drain`
stub in `lib/learn/learn.sh` ("currently REFUSES exit 1 -- you replace that stub"), and
`tests/test-bin-forwarders.sh` has a standing NC (`learn drain exits 1`) asserting that
exact refusal (added by SG-04, `docs/verification/loop-04-surface-consol.md` §e).
Decision: edited both, surgically:
  - `learn.sh`: only the `drain)` case arm + its usage comment lines; the `propose)` arm
    (SG-05's to unstub) is untouched.
  - `test-bin-forwarders.sh`: only the `learn drain` NC block (2 lines -> a dispatch
    smoke test); the `learn propose` NC block (SG-05's) is untouched.
Why: the file-fence list's own preamble frames it as scoping the NEW files created by
each sub-goal to avoid collision; it does not (and structurally cannot) name every file a
correctness-required dispatcher/test edit touches, and the goal file explicitly directs
this exact stub replacement. Leaving either file untouched would either not implement the
sub-goal's stated job (learn.sh) or ship a red CI test that was TRUE before this PR and
is now false (test-bin-forwarders.sh).
Alternatives: leave the drain case refusing and add a NEW verb name (contradicts ADR-0034
decision 1, which locked the verb name `learn drain`); leave the now-false NC in place
(ships a known-broken assertion).
Impact: both edits are line-disjoint from what SG-05 needs in the same files (SG-05 owns
the `propose)` arm and the `learn propose` NC block respectively) -- a low-risk, likely
clean merge either order. Full suites (`test-hooks.sh` 453/453, `test-meta.sh` 683/683,
`test-bin-forwarders.sh` 30/30) confirmed green after the edit.

## 2026-07-12 05:25 Numbering scheme: over the staged SUBSET, not all blocks

Context: the render needs "the numbered index add-backlog expects."
Decision: `drain.py::render` numbers 1..K over ONLY the currently-`staged` blocks, in
file order -- mirroring `add-backlog`'s `enumerate(staged, 1)` exactly, not
`enumerate(all_blocks, 1)` filtered afterward (which would have produced different
numbers once any block is promoted/rejected/expired).
Why: a number `learn drain` prints must always be safe to hand straight to
`board promote <n>`; verified directly (test-learn-drain.sh AC2, live numbering-parity
check against the real 69-candidate copy: index 3/4/60/63/69 matched exactly).

## 2026-07-12 05:30 Grouping/sort scope: within each Home group, not across the file

Context: "grouped by Home, age-sorted oldest-first" is ambiguous about whether the sort
is global or per-group.
Decision: sort within each Home group (oldest first), groups themselves ordered
alphabetically by Home name.
Why: a global age-only sort would scatter a Home's candidates across the render,
defeating the stated "what do I promote for repo X" grouping purpose; alphabetical group
order is deterministic and matches `lib/board/bin/add-backlog`'s existing convention of
not reordering by any heuristic.
