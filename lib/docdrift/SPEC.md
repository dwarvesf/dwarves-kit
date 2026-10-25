# docdrift module contract

The skill that drives this module is `skills/doc-drift/SKILL.md` (process step 3); the
pattern is `docs/patterns/audit-loop.md`. This file pins the invariants a change to
`refcheck.sh` must not break.

## Surface

```
refcheck.sh scan --repo DIR [--docs PATHSPEC]...
```

TSV on stdout: `doc`, `line`, `kind` (`tick` or `link`), `ref` for each dead reference, then a
`SUMMARY` row. Exit 0 when the scan ran, whatever it found; exit 2 on bad usage or a target
that is not a git repo.

## Tests

`bash tests/test-docdrift-refcheck.sh` (root-level, named for the module so
`tests/test-kit-contract.sh` C4 resolves it).

## Invariants

| # | Invariant | Enforced by |
|---|---|---|
| 1 | The scanner never writes to the target repo | reads only: `git ls-files`, file reads, `test -e` |
| 2 | A backticked ref is judged only when it holds a `/` and its first segment is a top-level entry of the repo | `tests/test-docdrift-refcheck.sh`, the sibling-repo case |
| 3 | A ref in a fenced code block, a URL, or a placeholder (`<` `*` `$` `~` `{` and kin) is never reported | the fence and placeholder cases |
| 4 | A tick resolves against the repo root, then each ancestor of the doc; a link against the doc's own directory | the resolution-rules cases |
| 5 | Exit 0 whenever the scan ran, dead refs or not | the exit case |
