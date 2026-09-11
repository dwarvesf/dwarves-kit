# lint: tool contract

What `scattered-ids.sh` guarantees to whoever edits it, or adds a zone. The rule it enforces is
CONTRIBUTING.md "Where an ID may appear"; the shape it follows is `docs/patterns/audit-loop.md`
(this is the loop's item-enumeration step, not the judge and not the fix).

## Surface

```
scattered-ids.sh --zone <name>              print every hit in that zone, path:line:text
scattered-ids.sh --all                      print every hit across every zone
scattered-ids.sh --zone <name> --count      print a bare hit count instead
```

Unknown zone: prints an error to stderr, exits 1. Everything else exits 0, including a zone
with zero hits: this script enumerates, it never judges a zone clean or dirty. That call
belongs to whatever calls it (`tests/test-no-scattered-ids.sh` for the ratchet).

## What counts as a hit

A line matching `(SPEC|TASK|ADR|SG|DEC|ID)-[0-9]+` in a tracked file inside the zone's glob,
unless the exemption list below drops it. The regex is the same one
`tests/test-no-scattered-ids.sh` zones 1/2 already used before this tool existed; a zone
migrated onto this script must report the same ids those zones already caught, or the ratchet
weakens instead of grows.

## Exemptions

| Exemption | Rule |
|---|---|
| Own-number header | the matched id also appears in the file's own basename |
| Frontmatter/key line | line starts with `Relates-to:`, `Backlog:`, `id:`, or `generated-by:` |
| Provenance footer | line matches `<!-- provenance: ... -->` |
| Board-row table line | line matches `| ID-nnn | ... |` |
| Dated log line | line starts with `YYYY-MM-DD` or `## YYYY-MM-DD` |
| `tool.toml` board array | line matches `board = [...]` |
| Test/fixture path | any path segment is `tests` or `fixtures` |
| Named exempt files | `docs/verification/gauntlet/**`, `docs/FEATURES.md`, `docs/CHANGELOG.md` |
| `printf` substitution | the line carries a literal `SPEC-%s` or `ID-%s` template, not a real id |

`hooks/commit-format.sh`'s guard regex (`SPEC-[0-9]|TASK-[0-9]|...`) needs no exemption entry:
it has no digit after the dash, so it never matches the id regex above in the first place. If
the guard regex ever grows a literal digit, add its line by name then; do not pre-build an
exemption for a shape that cannot occur today.

## Non-goals

- Does not fix a hit. `docs/patterns/audit-loop.md`'s apply step is a human (or an Edit-tool
  pass), never this script.
- Does not decide which zones must be clean. That is the ratchet in
  `tests/test-no-scattered-ids.sh`.
- Does not walk `docs/specs/`, `docs/decisions/`, or `_meta/` today: those buckets need
  per-file own-number-vs-cross-ref triage the census could not fully automate. The `docs-specs`
  zone exists so a future batch can start from it, not because this batch cleared it.
