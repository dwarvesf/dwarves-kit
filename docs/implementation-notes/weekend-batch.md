# Implementation notes: weekend-batch (SPEC-126)

Delta from the spec only; see `docs/specs/SPEC-126-weekend-batch.md` for the full design.

## 2026-07-03 16:20 the `response=` field lives on `gate-ledger.sh debt`, not a new writer

**Decision:** `mark-paid` needed a way to say "this rid is now closed" without inventing a second
ledger. Extended the EXISTING `debt()` subcommand with one additive, optional key
(`response=<engage|defer|wave>`), written between `verdict=` and `reason=`.

**Why:** SPEC-123's `debt()` is already the single writer for `| DEBT |` markers. SG-04 (not yet
built) will need the exact same "human said engage/defer/wave" concept for its ★-tap nudge. Rather
than SG-05 inventing its own closing marker and SG-04 inventing a second, different one later, this
spec fixes the field NOW as the shared contract both write through. `mark-paid` is simply the FIRST
caller that needed it.

**Impact:** `debt()`'s existing callers (`significance-classify.sh record`) are unaffected --
`response` defaults to empty, the line shape is identical to before when omitted. Existing
`grep -qE '\| DEBT \| significance=... verdict=...'` prefix-match assertions in
`tests/test-significance-classify.sh` still pass unmodified (verified: `bash tests/test-
significance-classify.sh` stayed 25/25 green after this change).

## 2026-07-03 16:35 the `pending` disposition (open tap, no response) is deliberately excluded

**Decision:** a `verdict=tap` line with no later `response=` is NOT collected by `list`/`collect`.

**Why:** ADR-0031's Refinement frames the ★-tap as SG-04's inline moment (Flow A): the human sees
"worth understanding: <why>" and picks engage/defer/wave right then. If the weekend batch scooped
up an open, unresolved tap, it would be making that choice FOR the human (silently converting "I
haven't decided yet" into "deferred") -- exactly the kind of untracked-decision failure ADR-0031
exists to prevent, just moved one level up. The batch only ever revisits what a human (or SG-02's
own silent-wave path) has ALREADY disposed of.

**Alternative considered:** collect `pending` items too, on the theory that an item still open a
week later is itself worth surfacing. Rejected for this sub-goal: SG-04 does not exist yet, so
there is no live inline moment for a `pending` item to have raced against, and manufacturing a
"stale tap" concept here would be speculating about a gate this repo has not built. If SG-04 lands
and a `pending` item genuinely goes stale (never resolved for weeks), that is a natural SG-04-side
follow-up (e.g. auto-timeout a stale tap to `defer`), not something SG-05 should invent from the
consuming end.

## 2026-07-03 16:50 impl-notes/explainer filenames don't reliably match the rid

**Decision:** `collect` tries TWO candidate filenames per artifact -- the rid itself
(`docs/implementation-notes/<rid>.md`) and the rid with a `ug-<NN>-` prefix stripped
(`docs/implementation-notes/<slug>.md`) -- reporting `found`/`absent` honestly either way.

**Why (the gap the spec's Problem section flags):** the corpus already has BOTH conventions. A
non-mega-goal run like `fix/cc-hyg-04-stop-tax` produces rid `cc-hyg-04-stop-tax`, and its
impl-notes file IS `docs/implementation-notes/cc-hyg-04-stop-tax.md` -- rid and slug match exactly.
But the understanding-gate mega-goal's own sub-goals (SG-02, SG-03) used the SHORTER feature slug
(`docs/implementation-notes/significance-classify.md`, `explain-command.md`), dropping the
`ug-02-`/`ug-03-` branch prefix their rid carries. There is no single deterministic rid->slug rule
across the whole corpus; AGENTS.md itself hedges with `<spec-slug>.md` (or `<feature-slug>.md`).

**Impact:** this is a best-effort resolver, not a guarantee. A rid using some THIRD naming
convention (neither of the two tried) reports `absent` even if a note technically exists under a
different name -- the digest still always surfaces the rid itself, so a human (or the dotfiles
skill) can find it manually. Not treated as a bug to fix further in THIS sub-goal: fixing the
corpus-wide naming inconsistency is out of scope (would touch SG-02/SG-03's already-merged
artifacts and every other repo's impl-notes).

## 2026-07-03 17:10 default repo scope = the repo you are standing in, not machine-wide

**Decision:** `list`/`collect` default to `--repo <basename of cwd's git root>` (matching the same
`repo=` value `gate-ledger.sh start()` writes); `--all-repos` opts into the full machine-wide
sweep, but then does NOT attempt impl-notes/explainer resolution (no local checkout path is
knowable for an arbitrary `repo=` name read out of the ledger).

**Why:** the debt ledger's `$LOG_DIR/runs/*.log` corpus is genuinely machine-wide (SPEC-097's
resolver, not per-repo), but `lib/explain.sh` and `lib/classify/significance-classify.sh` both already
resolve their own repo-relative paths off `git rev-parse --show-toplevel` of cwd. Matching that
convention means `weekend-batch.sh` behaves exactly like its siblings when Han (or the dotfiles
skill) `cd`s into a specific repo and runs it there -- the common case -- while `--all-repos`
covers the rarer "what did I defer/wave anywhere this week" sweep at the honest cost of unresolved
paths.

## 2026-07-03 17:20 a bash `set -e` / command-substitution pitfall (debugging note, not a design decision)

Not a design choice, but worth recording since it cost real debugging time and would bite the next
person editing this file: a helper function ending in a pipeline that can legitimately produce "no
match" (e.g. `grep -oE 'response=[^ ]+' | ... ` when the key is absent) must guard that pipeline
with `|| true` INSIDE the helper, not rely on the caller's context. Under `set -euo pipefail`,
whether `var="$(helper ...)"` aborts the whole script on a "no match" grep depends on bash's
nesting depth for command substitutions (a well-documented but easy-to-forget sharp edge:
`x=$(false)` at top level aborts a `-e` script immediately, but the identical pattern one function
call deeper sometimes does not, depending on bash version and how many `$()` layers deep it is).
`lib/queue/weekend-batch.sh`'s `_kv`, `_last_debt_line`, `_file_repo`, and `_find_artifact` all guard
their own pipelines with a trailing `|| true` (or an unconditional `return 0`) for exactly this
reason -- an "absent key" or "no ledger entry yet" is an expected, non-error result, never a
script-aborting one, and that has to be true regardless of how deeply nested the call is.
