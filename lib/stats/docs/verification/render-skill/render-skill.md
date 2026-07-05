# Proof of done: ledger-observatory feature `render-skill` (SG-03)

> Per-feature record. The canonical multi-feature index is
> [`../../proof-of-done.md`](../../proof-of-done.md); this file is its `render-skill`
> feature detail.

| | |
|---|---|
| **Profile** | data/CLI tool addition (behavioral, read-only, pure-function render layer) |
| **Proof class** | data-tool (recorded live run + negative control + reproducible) |
| **Spec** | [`../../specs/SPEC-128-render-skill.md`](../../specs/SPEC-128-render-skill.md) |

## Test design

`tests/test-render-skill.sh` covers the goal file's five-case run-table: trigger-fires
(a grep over `skill/SKILL.md`'s frontmatter for the required phrases), queries-via-02 (a
hand-written MOCKED `ledger query --json`-shaped blob fed straight into `render.py`'s pure
functions, plus a structural assertion that `render.py` imports nothing from
`materialize`/`adapters`/`duckdb`), terminal render (fenced code block, bold title, a
bar-fill column, row-count footer, an empty-rows placeholder), Artifact render (self-
contained `<!doctype html>`, inline `<style>`, no external `<script src=`/`<link href=`,
`prefers-color-scheme`, HTML-escaped values so a raw `<script>` in a ledger row cannot
break out), and the single-data-path negative control (one `rows` object fed to BOTH
formatters; a value appears in both; a mutation to that same object shows up in BOTH
re-renders, proving neither formatter reads from a second, cached, or divergent source). A
final `R-cli` block asserts the `ledger render` CLI subcommand structurally reuses
`materialize.show`/`materialize.query` (grep over `cli.py`), not a re-implementation.

## Confirmation run (recorded)

Command: `bash tests/test-render-skill.sh` , run 2026-07-03T20:28:28Z (UTC clock), exit 0.

```
== R-trigger: the frontmatter description carries the required trigger phrases ==
PASS  R-trigger 'show me the ledger state' / 'my debt' / 'telemetry' / 'token cost' / NOT-case present
PASS  R-trigger frontmatter parses as valid YAML
== R-queries-via-02: mocked --json input in, formatted surface out, no re-read ==
PASS  R-queries-via-02 no materialize import / no adapters import / no duckdb import
PASS  R-queries-via-02 terminal formatted from mocked json
PASS  R-queries-via-02 artifact formatted from mocked json
== R-terminal: bot-reply-formatting-shaped code-block table/bar surface ==
PASS  R-terminal fenced code block / has bold title / right-aligned bar-fill / row count footer / empty-rows placeholder
== R-artifact: valid self-contained Artifact HTML ==
PASS  R-artifact doctype / inline style / no external script / no external link / dark-mode aware / table present / escapes a raw tag / does not leak raw script tag
== R-nc: single-data-path negative control (SAME rows object, both surfaces) ==
PASS  R-nc same fixture value in both surfaces
PASS  R-nc a mutation reflects in both surfaces
PASS  R-nc no stale value survives the mutation
== R-cli: the ledger render subcommand wires to the SAME materialize read path ==
PASS  R-cli render command present / reuses materialize.show / reuses materialize.query

== 30 passed, 0 failed ==
```

Regression check on the same run: `bash tests/test-schema-conform.sh` (SG-01) 11/11,
`bash tests/test-ledger-cli.sh` (SG-02) 26/26 , the `ledger render` CLI addition and the
`render.py` import in `cli.py` introduced no regression in either existing suite.

## Self-review finding, folded in before this run (worth naming)

The first draft of `skill/SKILL.md`'s frontmatter `description:` contained an unquoted
colon inside the value (`"...in-terminal reply (bot-reply-formatting: tables +
bar-fills)..."` and one more in `"READ-ONLY by hard contract: the CLI..."`). Both grep
against fine (the trigger-phrase checks all passed), but the frontmatter did NOT parse as
YAML at all , a skill in that state cannot load in Claude Code, silently. Caught by an
explicit `python3 -c "import yaml; yaml.safe_load(...)"` self-review check (not by the
grep-based R-trigger cases, which only test substring presence). Fixed by rewording both
colons to the repo's existing " , " separator style (matching the rest of this doc's own
prose); a permanent regression guard (`R-trigger frontmatter parses as valid YAML`) was
added to the suite so a future edit that reintroduces an unquoted `word: ` inside the
description fails loudly instead of silently.

## Negative controls (falsifiability, load-bearing)

| NC | What | Result |
|---|---|---|
| NC1 single-data-path (the contract NC, SPEC-128 AC5) | construct ONE `rows` object; call `render_terminal(rows)` and `render_artifact(rows)`; assert a distinctive fixture value appears in BOTH; mutate the SAME object; re-render both; assert the mutation shows in BOTH and the stale value is gone from BOTH | all three assertions PASS , the two surfaces provably read from the one passed object, never a second source |
| NC2 deliberate break (falsifiability of NC1 itself) | patched `render_artifact` to discard the passed `rows` and substitute a hardcoded divergent object, then re-ran the suite | 4 cases went RED (`R-nc a mutation reflects in both surfaces` + 3 cascading `R-artifact` value assertions), exit 1 , confirms the NC actually exercises the single-data-path property rather than passing vacuously; reverted, suite back to 30/30 exit 0 |
| NC3 XSS/markup-break guard | a fixture row containing a raw `<script>alert(1)</script>` value rendered through `render_artifact` | output contains the HTML-escaped `&lt;script&gt;` form and does NOT contain the raw `<script>alert(1)</script>` tag , a hostile/odd cell value cannot break the Artifact's markup |
| NC4 structural read-isolation | grep `render.py` for `import materialize` / `import adapters` / `import duckdb` | none present , `render.py` cannot re-read a source even if it wanted to; the only read path is the CLI's `render` command, which calls the SAME `materialize.show`/`query` SG-02 already ships |

NC2, captured 2026-07-03 (deliberate single-data-path break; this run predates the
`R-trigger frontmatter parses as valid YAML` case added by the self-review finding
above, hence 29 not 30 in the restored count , the case count grew, the NC's own
logic is unaffected):

```
NC run exit code: 1
== 25 passed, 4 failed ==
FAIL  R-nc a mutation reflects in both surfaces (missing: MUTATION_REFLECTED_BOTH_OK)
restored run exit code: 0
== 29 passed, 0 failed ==
```

## Samples (real, captured from a live invocation , not hand-typed)

- Terminal: [`samples/terminal-sample.txt`](samples/terminal-sample.txt) , generated by
  `uv run ledger render kit_runs --surface terminal --limit 6 --title "kit_runs
  (recent)"` against the live rebuilt db.
- Artifact: [`samples/artifact-sample.html`](samples/artifact-sample.html) , generated by
  `uv run ledger render kit_runs --surface artifact --limit 6 --title "kit_runs (recent)"
  --out samples/artifact-sample.html` against the SAME live db state (same underlying
  query result as the terminal sample above, rendered through the other surface , this
  pair IS the single-data-path property demonstrated end-to-end via the real CLI, not just
  the unit-level NC).

## COVERAGE-DELTA

**Covered:** trigger-phrase presence in the skill frontmatter; the queries-via-02 contract
(pure-function correctness against a mocked `--json`-shaped input, plus the structural
no-re-read guarantee); both surface shapes (terminal fenced table with bar-fill, Artifact
self-contained HTML with dark-mode + escaping); the single-data-path NC (both the unit
level, with a deliberate break-and-restore, and an end-to-end pair of real CLI-generated
samples); the `ledger render` CLI subcommand's structural reuse of the existing read path.

**Left uncovered (named, not hidden):** (1) live Discord/Telegram rendering , the skill
only ever runs inside a Claude Code terminal reply, not an actual bot; `bot-reply-
formatting`'s code-block cell-budget/bar-fill discipline is followed, its Discord-embed
machinery is not invoked (out of scope, SPEC-128); (2) the Artifact tool's actual publish
call , that action can only be performed by the live agent in a real session, not by this
test harness (the harness proves the HTML `render_artifact` produces is valid + self-
contained; publishing it is a documented SKILL.md step, not code under test here); (3)
large-row-count / wide-table rendering performance , fixtures are small, matching SG-02's
own scope; (4) the actual skill install (`~/.claude/skills/ledger-observatory/`) , this PR
ships the source + a documented install pointer only, per the goal file's explicit
scope edge; SG-05's no-orphan check is the real installed-and-firing gate.

## Reproduce

```bash
cd ~/workspace/tieubao/ops-toolkit/tools/ledger-observatory
uv sync
bash tests/test-render-skill.sh    # 30 passed, 0 failed; exit 0
# regression check
bash tests/test-schema-conform.sh  # 11 passed, 0 failed
bash tests/test-ledger-cli.sh      # 26 passed, 0 failed
# real samples
uv run ledger rebuild
uv run ledger render kit_runs --surface terminal --limit 6
uv run ledger render kit_runs --surface artifact --limit 6 --out /tmp/ledger-sample.html
```

## Rollback

Additive-only branch (new `render.py` + one new `ledger render` CLI subcommand +
`skill/SKILL.md` + tests + docs under `tools/ledger-observatory/`; `cli.py` gains one
function, nothing removed or changed in `show`/`query`/`rebuild`/`tables`). No existing
runtime, daemon, or source ledger is touched; nothing is installed into
`~/.claude/skills/`. Rollback = `git revert` the branch, or delete `render.py` + the
`render` command; SG-01/02 are untouched either way.
