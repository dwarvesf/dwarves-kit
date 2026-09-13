# lint

Enumerates scattered spec/task/ADR/ticket ids that live outside their three sanctioned homes
(CONTRIBUTING.md "Where an ID may appear"). One script, `scattered-ids.sh`: print every hit, or
just a count.

## Use

```bash
bash lib/lint/scattered-ids.sh --zone hooks              # every hit in hooks/*.sh
bash lib/lint/scattered-ids.sh --zone commands --count    # just the count
bash lib/lint/scattered-ids.sh --all                      # every named zone
```

Exit 0 always: this is an enumerator, not a pass/fail gate. `tests/test-no-scattered-ids.sh`
decides which zones must come back empty and fails the suite when one does not.

## Zones

| Zone | Files scanned |
|---|---|
| `hooks` | `hooks/*.sh` |
| `bin` | `bin/*` |
| `skills` | `skills/*/SKILL.md` |
| `agents` | `agents/*.md` |
| `commands` | `commands/*.md` |
| `lib` | `lib/**/*.sh`, `lib/**/*.py` (nested `tests/` excluded) |
| `docs-specs` | `docs/specs/*.md` |

Adding a zone is a new `case` arm in `zone_files()`, nothing else.

## Exemptions

On top of the census pipeline's own exclusions, a hit is dropped when it is:

- an own-number header (the id also names the file itself)
- a frontmatter/key line (`Relates-to:`, `Backlog:`, `id:`, `generated-by:`)
- a provenance footer (`<!-- provenance: ... -->` in markdown, `# provenance: ...` in shell/python)
- a board-row table line (`| ID-nnn | ... |`)
- a dated log line (`YYYY-MM-DD ...` or a `## YYYY-MM-DD` heading)
- a `tool.toml` `board = [...]` array
- anything under a `tests/` or `fixtures/` directory
- `docs/verification/gauntlet/**`, `docs/FEATURES.md`, `docs/CHANGELOG.md`

Full contract: `SPEC.md`.

## Who calls this

`tests/test-no-scattered-ids.sh` (zones 3 onward). `docs/patterns/audit-loop.md`'s "loop
bridge" asks every audit-loop instance for a reproducible item-enumeration command; this is
that command for the scattered-id cleanup.
