# docdrift

Tier 1 path check of the `kit:doc-drift` audit loop. `refcheck.sh` reads living docs and prints one row per path reference that does not resolve. It is mechanical and costs no model tokens.

The skill that drives it is `skills/doc-drift/SKILL.md` (process step 3); the pattern is `docs/patterns/audit-loop.md`.

## Use

```
bash lib/docdrift/refcheck.sh scan --repo /path/to/repo
bash lib/docdrift/refcheck.sh scan --repo . --docs README.md --docs ':(glob)tools/*/README.md'
```

Output is TSV: `doc`, `line`, `kind` (`tick` or `link`), `ref`, then a `SUMMARY` line with the doc, ref and dead counts. Only dead refs are printed, so an empty body is a clean scan. Exit is 0 whenever the scan ran.

`--docs` takes a git pathspec and repeats. The default item set is the living-doc pathspec in the skill (a `:(glob)` pathspec is required: a bare `docs/*.md` matches recursively and pulls in dated records).

## What counts as a reference

| Form | Judged when | Resolved against |
|---|---|---|
| backticked token (`tick`) | it holds a `/` and its first segment is a top-level entry of this repo | repo root, then each ancestor directory of the doc |
| markdown link target (`link`) | it is relative (not a URL, `mailto:` or `#anchor`) | the doc's own directory |

A ref exists when it is a tracked file or directory, or is present on disk. A trailing `:LINE` or `:LINE-LINE` and any `#anchor` are stripped first.

## What it skips

Fenced code blocks, URLs, absolute paths, and any token with a placeholder character (`<` `>` `*` `$` `~` `{` `}` `|` `=` `,` `;` quotes, parens) or an `...` ellipsis. The first-segment rule drops paths into sibling repos, vendor trees and gitignored local files. That is the point: a hand-rolled version of this check returned about 900 hits on one repo, nearly all of them these.

## What it will not do

It never writes. It never leaves the repo it is pointed at. It does not check inventory tables, counts, or flags; those are the other Tier 1 bullets of the skill.
