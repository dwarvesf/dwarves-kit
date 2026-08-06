# WARM decisions ledger (append-only)

## 05-sessions-digest (2026-07-04, PR pending) -- GATE, field whitelist for Han's review

**THIS IS THE PRIVACY BOUNDARY.** The field whitelist below is VERBATIM (copied from SPEC-135's
Technical Design section) and is the exact and complete set of fields `read_sessions`/
`read_safety` (`tools/ledger-observatory/src/ledger_observatory/adapters.py`) ever read. No other
field on any transcript/log line is ever assigned to a variable, logged, or returned.

**`read_sessions` (Claude Code transcript `*.jsonl`), per line:**

- `type` -- routes parsing (`system` / `assistant` / `user`; every other `type` value is
  skipped entirely, e.g. `custom-title`, `last-prompt`, `agent-name`, `attachment`, `mode`,
  `permission-mode`, `file-history-snapshot`)
- `subtype` -- system lines only, checked `== "compact_boundary"` for the compaction counter
- `timestamp` -- ISO8601 string, used for the session's `first_ts`/`last_ts`/`duration_s`
- `message.usage.input_tokens` / `.output_tokens` / `.cache_read_input_tokens` /
  `.cache_creation_input_tokens` -- assistant lines only, summed into the session's token totals
- `message.stop_reason` -- assistant lines only, checked `!= "tool_use"` to know whether a turn
  is terminal (for the canary check)
- `message.content[].type` -- checked against `"tool_use"` (assistant lines, counted),
  `"tool_result"` (user lines, checked alongside `.is_error`), `"text"` (assistant lines only)
- `message.content[].is_error` -- `tool_result` items on `type=="user"` lines ONLY; summed into
  `error_count` when truthy
- `message.content[].text` -- `text` items on `type=="assistant"` lines ONLY, read TRANSIENTLY:
  the LAST text block of a terminal turn is checked for whether it ends with the
  adherence-canary marker (`🐱 Neko-san`); this produces ONE boolean (`canary_drop_count += 1` on
  a miss). The string itself is never appended to any accumulator, never logged, never returned.
  A `type=="user"` line's own `text` (a real user prompt) is NEVER read, not even transiently --
  a STRICTER rule than the assistant-text case.

`project_slug` and `session_id` come from the FILESYSTEM path (the parent directory name / the
`.jsonl` filename stem), never a per-line field -- `cwd` and `sessionId` are never read at all.

**Fields NEVER read, under any code path:** `cwd`, `sessionId`, `gitBranch`, `model`, `uuid`,
`parentUuid`, `message.content[].input` (a `tool_use` block's own arguments),
`message.content[].content` (a `tool_result` block's raw payload -- CONFIRMED during design-time
probing to carry raw file text verbatim, e.g. an Edit error literally quoting surrounding file
prose), `custom-title`, `last-prompt`, `agent-name`, `attachment`, `hookAdditionalContext`,
`toolUseResult`, `prUrl`, `compactMetadata` (any sub-field), or any other key on any line.

**`read_safety` (`~/.cache/claude-secret-guard.log`), per line:** ONLY the leading 4-5
bracket-delimited groups via a fixed regex: `ts`, `status`, `session`, `tool`, an optional `rule`
code. The free-text remainder of every line (confirmed during design-time probing to sometimes
carry a real file path, e.g. `/tmp/pt.json`, a `dotfiles/tests/secret-guard.sh` path) is
deliberately OUTSIDE any capture group -- it is matched by nothing and can never end up in a row.

**Materialized schema (the only columns that can ever hold data):**

```
sessions: session_id, project_slug, first_ts, last_ts, duration_s,
          input_tokens, output_tokens, cache_read_tokens, cache_creation_tokens,
          tool_call_count, error_count, compaction_count, canary_drop_count
safety:   ts, status, session, tool, rule
```

Every column above is a number, a timestamp, or a short filesystem/log-derived slug. No column
in either schema is, or can ever hold, free-text message content.

**Proven falsifiable (not just asserted):** the load-bearing privacy negative control (a fixture
transcript embedding a fake secret in BOTH `tool_result.content` and `custom-title`) passes
(zero hits across every materialized table/column) on the shipped code, and was proven NOT
vacuous by a deliberate break: temporarily widening `SESSIONS_SCHEMA`/`_parse_session_file` to
also capture the raw `tool_result.content` value turned the same check RED (`HITS: 1`), restored
via `git checkout --`. Full detail: `tools/ledger-observatory/docs/verification/sessions-digest.md`
"PRIV-nc falsifiability".

- **DEC-005-01 (a real Build-time bug, SPEC-135 DEC-007):** `tool_result`/`is_error` was
  confirmed to live on a `type=="user"` line (the tool-result turn Claude Code synthesizes back
  to the model), NEVER the `type=="assistant"` line that emitted the matching `tool_use` --
  `error_count` silently stayed 0 across the entire real corpus (6706 sessions) before this was
  caught via a real smoke run. Fixed by also scanning `type=="user"` lines, but STRICTLY only for
  the already-whitelisted `content[].type`/`.is_error` fields; that line's own `text` (a real
  user prompt) is never read at all.
- **DEC-005-02 (a real cross-suite regression, the SG-03 isolation-lesson repeated a third
  time):** every EXISTING test suite's `ledger rebuild` call defaulted the two new adapters to
  the REAL `~/.claude/projects/` (2.1GB/8179 files) and the real secret-guard log the instant
  this sub-goal landed, since none of those suites isolated the two new source env vars
  (`LEDGER_OBS_SESSIONS_DIR`/`LEDGER_OBS_SECRET_GUARD_LOG`). `test-anomalies-advisor.sh` timed
  out entirely (15+ real-corpus `rebuild()` calls at ~25s each). Fixed by adding the same
  isolation-line convention SG-03 established for `LEDGER_OBS_GIT_REPO_DIR` to all 7 affected
  suites, plus updating `test-anomalies-advisor.sh`'s now-stale `T-not-armed` docstring
  assertion (SG-04's stub is intentionally armed by this sub-goal) to `T-armed`.
- **DEC-005-03 (`_detect_token_runaway` armed as a flat per-session threshold, not per-rid):**
  `sessions` carries no rid/repo column in v1 (a session transcript has no structural link to a
  kit rid); arming the detector against a "per-sub-goal budget" would need the SAME
  time-containment bridge `ledger digest`'s cost-per-verified-outcome JOIN builds, duplicated
  inside a detector for marginal benefit. Chosen instead: flag the single highest-total
  `sessions` row over a flat `token_budget_max` (default 50,000,000 -- deliberately loose, since
  cache-read tokens are billed PER assistant turn, not once, so even a normal long session can
  legitimately sum into the tens of millions), matching every other detector's single-shot,
  worst-match shape.
- **DEC-005-04 (`digest`'s cost-per-verified-outcome JOIN bridges by TIME containment, the
  bridge technique proven a FIFTH time):** `sessions` carries no file list to compare (unlike
  `git_fixes`), so the SAME two-stage name-then-genuine-fact bridge technique SG-02/03/04 already
  proved (name-match a shipped `kit_gates` rid to a git commit subject once, then correlate by a
  genuine shared fact thereafter) substitutes TIME CONTAINMENT (the commit's timestamp falling
  inside a session's `[first_ts, last_ts]` window) for file equality. On the real corpus, this
  bridge yields the SAME honest-empty result SG-02/03/04 already documented (no real `kit_gates`
  rid's substring matches any commit subject here today), reconfirmed via a DIFFERENT bridge
  dimension.
- **DEC-005-05 (a CRITICAL content-leak path, found by `kit:code-reviewer` on the FINISHED diff
  -- the two-review-rounds lesson paying off exactly as SG-04 predicted for this sub-goal):** a
  bare `int(usage_field)` on a valid-JSON-but-non-numeric transcript field raised a `ValueError`
  whose message embedded the field VERBATIM; uncaught, it reached a CLI traceback and printed
  transcript-sourced content in the clear (reproduced live by the reviewer). This is the EXACT
  class of leak this sub-goal exists to prevent, on a code path the draft-stage
  `/kit:spec-validate` could not have seen (it lives in the implementation, not the design).
  Fixed with a `_safe_int` helper + a broad per-line `except Exception: continue`; the new
  `O-badtype` fixture proves it falsifiably (planted secret-shaped string -> `rebuild` exit 0,
  zero hits in any column, absent from output). Lesson reconfirmed for 06: a finished-diff code
  review catches a DIFFERENT and sometimes HIGHER-stakes bug class than a draft-stage spec
  review; run BOTH for any privacy/security-critical work.
- **DEC-005-06 (a MAJOR cost double-count, same review):** the digest cost-JOIN was 1:N across
  overlapping concurrent sessions (parallel worktrees/subagents = the norm here, not an edge
  case) and summed all of them, inflating the headline metric; `avg_time_to_done_min` used a
  different attribution than cost. Fixed with a closest-preceding-session `QUALIFY` so cost +
  time-to-done share one model (`D-overlap` fixture: two overlapping sessions -> cost from the
  closest-preceding one only, not the sum).
- **DEC-005-07 (a MINOR, same review):** the one accepted-verbatim field (`timestamp`) now gets
  a light ISO8601 shape-gate; a junk string is dropped (that line's ts contribution only), never
  persisted raw into `first_ts`/`last_ts` (`O-badts` fixture).

## 01-kit-gates-lens (2026-07-04, PR #683)

- **Parser tolerance grammar** for `adapters.read_kit_gates` (per-line `\| GATE \|`/`\| OUTCOME \|`
  reader): a line with fewer than 4 `" | "`-delimited fields (severely malformed, e.g. a
  concurrent-write truncation) is SKIPPED, never raises, never fabricates a gate/outcome from
  partial data. A `GATE` line with exactly 4 fields (no reason segment) sets `reason = None`, the
  row is still emitted. An `OUTCOME` bracket's `at=`/`caught=` tokens are parsed permissively
  (`key=value`, whitespace-split); a non-numeric `at=` value is kept as its RAW string (no cast,
  no exception); a `caught=` value that is not literally `true`/`false` (case-insensitive) leaves
  `caught = None`, never a truthy/falsy guess. A gate name recorded more than once within one
  `rid` produces one row PER `GATE` line (never deduped); completed `OUTCOME` brackets for that
  phase pair to those rows FIFO in file-encounter order, so the Nth occurrence of a gate gets the
  Nth completed bracket for that phase (or `NULL` if fewer brackets than GATE lines exist). An
  `OUTCOME` start with no matching end (unclosed bracket) never pairs to anything and is silently
  dropped from the FIFO queue, it does not leak a stale/partial value onto a later row.
- **Two-marker join is deliberate, not a workaround**: `caught`/`start_ts`/`end_ts` come from a
  SEPARATE marker type (`\| OUTCOME \|`, kit's own SPEC-129) than `gate`/`outcome`/`reason`
  (`\| GATE \|`), written by two different `gate-ledger.sh` subcommands (`record` vs. `outcome`).
  They are joined by matching PHASE NAME only, never assumed adjacent or co-occurring.
- **100% NULL `caught` on the real corpus is correct, not a bug** (verified 2026-07-04 by scanning
  every file under `~/.local/state/dwarves-kit/logs/runs/*.log`: zero contain a real `\| OUTCOME \|`
  line; the emitter lands via the kit-absorptions sibling mega). The FP negative control in
  `tests/test-gate-yield.sh` (`ui-design`, 2 legitimate skips, zero caught signal) asserts this
  state is reported honestly (skip count visible, `caught=0`, never dropped, never mislabeled as
  ceremony), proven load-bearing by a deliberate break (force `caught = True` unconditionally ->
  15/25 RED, restored -> 25/25).
- **`read_kit_gates` is a documented exception to the "reuse `_rows()`, no re-parse" rule**
  (`kit_runs`'s own adapter docstring): `_rows()` aggregates per-file with no per-line output mode,
  so there is no existing per-line reader to reuse for a per-`GATE`-line table. Scoped narrowly to
  this one grammar line; does not open the door to re-parsing anything `_rows()` already exposes.
- **Golden fixture is COMMITTED** (`tests/fixtures/kit-gates/runs/*.log`), not generated in a
  `mktemp` per test run like every other suite in this tool, per the goal file's explicit
  requirement so the exact fixture content is inspectable/diffable in the PR.
- **Pre-existing, unrelated environment issue found**: `tests/test-ledger-cli.sh` fails 7/26 in
  this local environment (`kit_runs` returns 0 rows; `read_kit()`'s subprocess into the installed
  `lane-telemetry.sh` returns nothing here). Confirmed via `git stash` to predate this branch
  entirely; `kit_gates`/`read_kit_gates` never touch `read_kit`/`lane-telemetry.sh`. Not
  investigated further (out of scope per SPEC-131's scope fence: "Not: rewriting `kit_runs`").

## 02-defect-correlation (2026-07-04, PR #684)

- **The JOIN-key decision (flagged upfront by the conductor):** `kit_gates` v1 carries no
  per-file or per-repo column, so a literal "JOIN on shared files" between a shipped run and git
  history is impossible without rewriting `kit_gates` (out of scope). CHOSEN: a TWO-STAGE bridge,
  not a single coarser join. Stage 1 bridges `kit_gates.rid` to git by a textual match
  (`contains(lower(subject), lower(rid))`), verified to have real signal empirically (the rid
  `dag-wavefront` is a literal substring of dwarves-kit's actual `feat(orchestrate): DAG-wavefront
  scheduling ...` commit subject). Stage 2 then correlates by GENUINE FILE EQUALITY between the
  earliest bridge-matched commit's own files and a later fix()-typed commit's own files. This
  keeps the goal's literal "touching the same files" wording honest instead of degrading to a
  name-only heuristic (rejected: correlating purely by "does a later fix() commit's subject also
  mention the rid", which drops file granularity entirely).
- **Windowing is anchored on GIT timestamps, not `kit_gates`/`kit_runs`.** Both of the obvious
  timestamp sources are broken in this environment: `kit_gates.start_ts`/`end_ts` are 100% NULL
  on the real corpus (SPEC-131 DEC-003, no OUTCOME emitter fires yet) and `kit_runs` returns 0
  rows in this local dev environment (`read_kit()`'s subprocess into the installed
  `lane-telemetry.sh` fails here, the SG-01-flagged pre-existing issue, reconfirmed on this
  branch). A design anchored on either would have produced a silently-empty real run. `--window-
  days` (default 30, tunable) is real git-timestamp math: `git_fixes.ts` for both the bridge
  match and the later fix commit.
- **`git_fixes` stores the FULL commit history, not fix()-filtered**, despite the literal table
  name (kept per the goal file's outcome section verbatim). Fix-classification happens at query
  time (`regexp_matches(subject, '^fix(\(.*\))?!?:')`), the same convention `gate-yield` already
  uses for `outcome` classification in SQL rather than in the adapter. Rationale: one table has
  to answer BOTH sides of the correlation (which commit shipped a run, which later commit fixed
  it); pre-filtering to fix-only at the adapter level would lose the first side entirely.
- **Rename handling (v1 limitation, not solved here):** `ship_files` only ever contains the
  EARLIEST bridge-matched commit's own file list. A rename occurring in or after that anchor
  commit is NOT followed: a fix on a post-rename filename is invisible to that rid's row. Proven
  via the `renamer` fixture case (the anchor's own file `old.py` stays tracked and `clean`; no
  `new.py` row exists at all for that rid, not a crash, a stated limitation). Real
  rename-following (`git log --follow`-equivalent) is out of scope for v1.
- **Merge commits are excluded via `--no-merges`** at the adapter level (not filtered on
  content): this repo's real merges are GitHub squash-merges producing one linear conventional
  commit already, so a true 2+-parent merge carries no useful file list. Proven via a fixture
  merge commit whose subject textually matches a rid AND looks like a fix() commit -- confirmed
  absent from `git_fixes` entirely via direct adapter inspection, not just absent from the
  correlation output (which could hide a subtler leak).
- **Golden fixture is GENERATED at test time** (`git init` in `mktemp -d` + controlled
  `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` commits), not a committed nested repo. A nested `.git`
  tree does not commit cleanly as tracked files in this repo (no submodule machinery was
  warranted for a disposable fixture); the goal file explicitly allows "a committed mini
  git-history fixture (OR a fixture table)", and every other suite in this tool already uses this
  same mktemp-per-run precedent. `git init --template=` is required when building ANY throwaway
  fixture repo on this machine: `init.templatedir=~/.git_template` (global git config) copies a
  Conventional-Commit-enforcing `commit-msg` hook into every `git init`'d repo by default, which
  rejects the fixture's deliberately-varied test subjects unless disabled per-repo.
- **Real-history yield is low, stated honestly, not hidden:** across both scanned repos
  (`ops-toolkit`, `dwarves-kit`), only 1 of ~600 distinct shipped `kit_gates` rids resolves via
  the rid-substring bridge at all. Most kit run slugs are not literal substrings of the eventual
  commit subject in either repo's Conventional-Commit history. The one hit that DOES resolve
  (`dag-wavefront`) is real (2 later fix() commits on `_meta/BACKLOG.md`, a broadly-touched
  housekeeping file -- a legitimate but noisy signal, since almost any PR touches that file).
- **`test-feedback.sh`'s 9/39 failure is newly confirmed pre-existing**, not caused by this
  branch: reproduced identically via `git stash` (same 30/9 split with none of this PR's changes
  applied). Adds to the SG-01-flagged `test-ledger-cli.sh` 7/26 pre-existing issue; neither is
  fixed here (out of scope).

## 03-deviation-rate (2026-07-04, PR #687)

- **Shared repo-root config knob, not a second one:** `impl_notes` reuses
  `config.git_repo_dir()` / `LEDGER_OBS_GIT_REPO_DIR`, the SAME knob `git_fixes` already uses,
  rather than a second `LEDGER_OBS_IMPL_NOTES_DIR`. `deviation-rate`'s SUSPECT/CLEAN
  classification JOINs the two tables; a second knob would let an operator override one and
  forget the other, silently making the join describe two different repos with no error.
- **The JOIN-key decision (the SAME shape as SPEC-132 DEC-002, now proven twice):**
  `impl_notes` carries a `slug` (a filename stem), never a sha or a file list of its own.
  CHOSEN: the identical two-stage bridge SG-02 already proved sound -- bridge `slug` to git via
  `contains(lower(subject), lower(slug))`, then correlate by genuine FILE EQUALITY against that
  anchor commit's own files for the actual SUSPECT determination. `UNDER-SPECCED` needs no
  bridge at all: it is a pure `n_deviations >= --under-specced-min` count threshold, independent
  of any git data.
- **Class thresholds are named tunables (per the goal file's requirement):**
  `--under-specced-min` (default 3, the goal's literal `>= 3 deviations` cutoff) and
  `--window-days` (default 30, same convention/name as `defect-correlation`'s tunable) are both
  Typer CLI options interpolated as plain ints into fixed SQL positions, never buried constants.
  Both proven real in the test suite by re-running the SAME fixture data at a second value and
  observing the classification flip (I-window, I-tunable).
- **Malformed-file policy:** a file carrying BOTH the zero-marker line AND one or more real
  entry headers (a self-contradiction; confirmed present in the real corpus, e.g.
  `tools/vps-mon/docs/implementation-notes/SPEC-075-mini-launchd-collector.md`) is counted as
  entries (`n_deviations` = the real header count), `zero_marker` is forced `False` (a file that
  logged real deviations is never treated as the honest-zero case regardless of what its marker
  line claims), and a stderr warning is logged (non-fatal; the row is still returned). Rationale:
  silently trusting the marker's claim at face value would hide an internally inconsistent file
  rather than surface it.
- **The parser tolerates real, confirmed prose drift on BOTH hook-enforced shapes:** the entry
  header's `HH:MM` time component is frequently dropped entirely in the real corpus (many
  headers are just `## YYYY-MM-DD <title>`); the zero-marker line's trailing wording varies
  (e.g. "No deviations from spec; no reconcile bug found." vs. the canonical "No deviations;
  matches `<spec>` verbatim"). Both are matched by their LEADING shape only (a date optionally
  followed by a time for entries; a leading "no deviation(s)" phrase, optional bullet stripped,
  for the marker), never the exact canonical wording. A `## `-prefixed title merely MENTIONING
  "no deviation" as prose (confirmed real, e.g. "## 2026-06-14 Shipping mechanics (no deviation
  from spec, two host quirks)") can never match the marker regex (it anchors on the line's own
  start, and a header line starts with `#`), so it is correctly counted as a real entry, never
  mistaken for the marker.
- **The 4th bucket, `OTHER`, is a deliberate, honest addition beyond the goal file's 3 named
  classes.** A file with 1-2 logged deviations and no zero-marker (not concerning either
  direction), or a file predating the hook's entry-header/marker convention entirely (confirmed
  present in the real corpus as free-form legacy prose with neither shape), must not be silently
  coerced into CLEAN, UNDER-SPECCED, or SUSPECT. Named plainly rather than hidden inside one of
  the three.
- **A real cross-suite regression, found and fixed during Build (not anticipated by the goal
  file):** `test-ledger-cli.sh`/`test-feedback.sh`/`test-gate-yield.sh` never isolated
  `LEDGER_OBS_GIT_REPO_DIR` (SG-02's `git_fixes` already silently defaulted to the real repo in
  these suites too, but emits no stderr and adds no anomaly detector, so it never surfaced).
  `impl_notes` introduces two new failure surfaces once left un-isolated: a stderr warning from
  the malformed-file check leaking into a byte-identical remat comparison
  (`test-ledger-cli.sh`), and, far more seriously, `unknown-density` spuriously firing against
  the real corpus's genuine deviation density inside `test-feedback.sh`'s LOAD-BEARING
  `F-nc-noise` negative control (a noise-floor state must propose NOTHING). Fixed with one
  `LEDGER_OBS_GIT_REPO_DIR="$FIX/nonexistent-git-repo"` isolation line added to each of the 3
  suites (matching their existing "absent -> skip-safe" convention for the other env vars, zero
  assertion-logic changes); `git stash` before/after confirmed each suite's EXACT documented
  pre-existing pass/fail count restored.
- **Real-corpus yield: zero rows carry `zero_marker=true` in EITHER scanned repo
  (`ops-toolkit` 233 rows, `dwarves-kit` 77 rows), stated honestly, not hidden.** CLEAN and
  SUSPECT are both empty in the real run, not because the classifier is broken (proven correct
  against the golden fixture, including the load-bearing honest-zero NC and its deliberate-break
  falsification), but because the real corpus has not yet produced a genuinely
  honest-zero-deviation implementation-notes file: every real file surveyed either logs at least
  one real dated entry, or predates the hook's convention entirely (the `OTHER` bucket). Two
  malformed files were also confirmed real in the corpus (the `SPEC-075` file above and
  `tools/safari-tabs/extension/docs/implementation-notes/parity-verbs.md`).
- **Nested worktree pruning:** `read_impl_notes`'s directory walk prunes any hidden directory
  (`.git`, `.venv`, and critically any `.claude/worktrees/<x>` copy of the SAME repo). Confirmed
  necessary in practice: dwarves-kit carries a live nested worktree under `.claude/worktrees/`
  that would otherwise physically double-count every `docs/implementation-notes/*.md` file
  underneath it.
- **Golden fixture is GENERATED at test time** (`git init` + controlled
  `GIT_AUTHOR_DATE`/`GIT_COMMITTER_DATE` commits in `mktemp -d`), matching SPEC-132 DEC-005's
  precedent exactly. The implementation-notes fixture files themselves are plain (untracked)
  files under the fixture repo -- `read_impl_notes` is a filesystem walk, not a git read, so
  git-tracking them is not required.
- **A local-environment quirk discovered while committing (not a bug in this sub-goal's code,
  worth flagging for 04+):** a PreToolUse hook statically scans the raw Bash command text for a
  `git commit -m "..."` shape and validates whatever text falls inside the quotes as the literal
  commit subject. A `-m "$(cat <<'EOF' ... EOF)"` heredoc construct trips this (the hook grabs
  the ENTIRE command-substitution text as "the subject", which obviously fails the
  Conventional-Commit/72-char checks). `git commit -F <file>` (write the message to a file, then
  `-F` it) avoids the false positive entirely and is what this branch's commits use.

## 04-anomalies-advisor (2026-07-04, PR pending)

- **`_detect_serial_when_parallel` redesigned mid-Build, away from `kit_runs`:** the goal file's
  own wording ("over a run's duration") pointed at `kit_runs.first_ts/last_ts`. Confirmed
  empirically that `kit_runs` returns 0 rows in this local environment (a controlled fixture with
  well-formed START/GATE lines still produced zero `adapters.read_kit()` rows) -- root-caused to
  a `bash 3.2` (`/bin/bash` on this machine) `source`/`return`/`set -e` interaction: sourcing
  `lane-telemetry.sh` and letting `main "$@"` `return 64` (no subcommand) aborts the WHOLE calling
  script despite the `|| true` guard `adapters.read_kit()` already uses. This is the SAME root
  cause behind `test-feedback.sh`'s 9/39 pre-existing failures (its debt/misfire fixtures also
  depend on `kit_runs`), now traced one level deeper than SG-01/02/03 left it ("not investigated
  further"). Redesigned before any fixture was written to window every `kit_gates` rid by
  `MIN(ts)..MAX(ts)` across its OWN git-bridged commits instead, per HANDOFF's standing windowing
  lesson (`git_fixes.ts` is the one reliable timestamp). `_detect_serial_when_parallel` never
  touches `kit_runs`, `adapters.py`, or `materialize.py`.
- **`/kit:spec-validate` dispatched on the DRAFT design** (the `kit_runs`-anchored advisor, a raw
  `count(*)` bridge-evidence query) and returned NEEDS-REVISION with 2 CRITICAL + 3 MAJOR
  findings. Both CRITICALs were real, non-hypothetical bugs in the draft: (1) `mention_files` is
  `(gate, rid, file)` grain, so counting `count(*)` for the ceremony detector's "bridged" evidence
  floor let a SINGLE multi-file commit fake evidence-sufficiency for a gate with only one real
  invocation (fixed: `count(DISTINCT rid)`); (2) no acceptance criterion exercised "a gate with
  evidence-sufficient KNOWN caught data where even ONE sample is true" as distinct from the
  min-sample floor (fixed: a new `C-mixed` fixture). The 3 MAJOR findings (the advisor's missing
  evidence floor letting a zero-git-correlation pair fire vacuously; ambiguous inheritance of
  `defect-correlation`'s `gate='ship'` filter; `serial_min_minutes_saved=1.0` too permissive to do
  real filtering) were folded into the `git_fixes`-anchored redesign above (the evidence floor is
  now structural, via INNER JOINs) and a threshold bump (1.0 -> 10.0). Not re-dispatched for a
  second full adversarial pass once fixed (the fixes are narrow, each mechanically verified by a
  new fixture, and proportionate to the obvious-design tier); see SPEC-134 "Review".
- **Ceremony's two conditioning signals, never a bare skip-rate:** hard (`caught`, when the gate
  has >= `ceremony_min_ran` KNOWN-caught runs) fires CUT if none is true; soft (fix-correlation
  proxy via the SAME rid-to-git bridge `defect-correlation` uses, generalized from `gate='ship'`
  to every gate) fires CONDITION only when `caught` is thin/absent AND >= `ceremony_min_ran`
  bridged rids show zero later fix(). The FP-NC (`ui-design`, ~80% skip for a legitimate reason,
  real `caught=true` in its few ran rows) proves neither path is fooled by skip fraction; a
  hand-built bare skip-rate query run inline (not shipped code) confirms it WOULD have flagged it.
- **Token-runaway wired but never armed:** no materialized table carries a per-run token/cost
  figure (lands with sub-goal 05's sessions adapter). `_detect_token_runaway` always returns
  `None` today, kept in the `DETECTORS` tuple so `detect()`'s shape and the `--propose` path need
  zero re-plumbing once 05 lands. Never faked, per the same discipline `unknown_density` applied
  to its own honest-empty real-corpus yield in SG-03.
- **Real-corpus yield is honestly empty for all 3 new detectors**, same conclusion as SG-03's
  `unknown_density` precedent: `defect-correlation` itself already returns 0 rows on this real
  corpus (no real `kit_gates` rid's substring matches any commit subject here), so the git-bridge
  both new detectors depend on has nothing to work with; ceremony's hard path also has only 3
  `caught_known` samples total (all `ship`, all false), below the 5-sample floor. The classifiers
  are proven correct against the fixtures (incl. the FP-NC); the real corpus has simply not yet
  produced a case for either to catch.
- **A second, independent review round caught a real bug the first missed:** `kit:code-reviewer`
  was dispatched on the FINISHED diff (not the draft `/kit:spec-validate` reviewed) and found a
  MAJOR: `caught_true > 0: continue` only lived inside the `caught_known >= ceremony_min_ran`
  branch, so a gate with THIN caught data containing a real catch could still fire CONDITION via
  the soft/fix-correlation path -- the exact false-positive shape this detector exists to avoid,
  just via a different code path than the draft-stage review checked. Fixed by hoisting the guard
  to run unconditionally before either branch; falsifiable (a new `C-thin-true` fixture goes RED
  when the guard is reverted, green when restored). Lesson for 05/06: a draft-stage adversarial
  pass and a finished-diff code review catch DIFFERENT bug classes (the former the design's
  logical shape, the latter where the actual code diverges from that shape); both are worth
  running, not either/or.

## 06-memory-lens (2026-07-04, final PR HELD) , extraction heuristics + staleness threshold

- **Conservative reference extraction (DEC-008/009, PATHS-ONLY after the real-corpus run):** the
  sweep tests ONLY inline code-span tokens, and only if clearly path-like: an absolute path under
  a recognized real filesystem root (`_REAL_PATH_PREFIXES`: `/Users/`, `/etc/`, `/opt/`, `/tmp/`,
  ...), or a `~/...`/`~user` home. Command-testing was in the draft (`shutil.which()` on a bare
  word) and was REMOVED ENTIRELY (DEC-008): the FIRST real `ledger memory-sweep` run flagged
  135/248 units, overwhelmingly junk , bare backtick words (`README.md`, `main`) and shell
  builtins/keywords (`trap`, `export`, `const`) `which()` cannot resolve. Leading-`/` tokens NOT
  under a real root are skipped too (DEC-009): the dominant leading-`/` false positive was Claude
  Code slash-commands (`/goal`, `/kit:spec`) and REST fragments (`/v1/chat/completions`),
  syntactically a path but never one. Bare relative paths, flags (`--foo`), prose paths (no
  backticks), placeholders (`<x>`/glob/brace), and `://` URLs are all SKIPPED. Net on the real
  corpus: 135 -> 33 units flagged, junk gone, real dead paths kept. A false dead-ref costs trust;
  under-flagging is the safer error for a v1 precision proxy.
- **IS-IT-AN-INDEX gate for MEMORY.md (DEC-010):** the draft flagged every no-link bullet in a
  MEMORY.md as a dead orphan, assuming every MEMORY.md is a `[title](slug.md)` link index. Real
  finding: some are free-PROSE scratchpads (`claude-guardrails`'s is 39 prose bullets, none a
  link) , flagging all 39 was noise. A MEMORY.md with ZERO link bullets now contributes NO refs;
  only a file with >= 1 real link bullet has its no-link siblings read as genuine orphans. Keeps
  the real signal (the ops-toolkit builtin MEMORY.md's 2 `MIGRATED` tombstones, alongside real
  link bullets) and drops the guardrails noise (39 -> 0).
- **`~user` RuntimeError is caught, not propagated (DEC):** `Path("~nonexistent-user/...").
  expanduser()` raises `RuntimeError` on this platform (a real bug found via the first real-corpus
  run against `~server/...`-shaped notes). The resolver catches it and flags the ref dead rather
  than crashing the whole sweep. A note may carry MULTIPLE such refs (the fixture carries two:
  `~nonexistent.../some/path` and `~server/...`), so the honest count is `dead=2`, not 1.
- **Staleness threshold = 180 days (DEC):** a note whose `written` (git-commit date for the repo
  store, mtime fallback for the non-git builtin store) is older than 180 days is stale-flagged.
  Named tunable, not a buried constant.
- **NEVER-DELETE is absolute (Han's rule):** the sweep is propose-only and holds no write path to
  any memory store. The load-bearing NC sha256s every memory file before/after the full
  sweep+rebuild+anomalies and asserts byte-identical; proven falsifiable via a deliberate
  in-fixture mutation that flips the same comparison red.
- **v2 deferred (coverage-delta):** global `~/.claude/CLAUDE.md` reference sweeping is out of
  scope for v1 (STORES only); runtime recall instrumentation and any auto-fix of dead memories
  are explicitly not built (propose-only, manual weekend-batch paydown, no daemon).
- **Recovery decision:** the SG-06 worker was interrupted mid-run (a monthly spend-limit) after
  committing 6 phase boundaries + opening PR #691. On resume, the worker found the source already
  carried the DEC-008/009/010 precision fixes (committed) but the proof docs (proof-of-done.md
  recorded-run + verification/memory-lens.md) still carried the STALE pre-DEC-010 numbers (33/33,
  memories:12, guardrails 39-dead). Reconciled all proof docs to the committed reality: 39 tests,
  13 fixture units, 248 real memories / 33 carrying dead refs, guardrails 0 (DEC-010), the
  ops-toolkit MIGRATED tombstones still caught. No source/logic behavior changed in the reconcile
  , docs-only drift correction.
