# Proof of done: docs index expansion (SPEC-114, kit-face wave)

`docs/README.md` extends into a navigable thematic map , adding the two record classes the quick
map omitted (`implementation-notes/`, `verification/`) + a `lib/spec/spec-index.sh` pointer for the
specs , with the 23-line front door byte-identical and no rotting counts.

## Acceptance criteria

| # | Criterion | Result |
|---|---|---|
| 1 | Front door (intro + What's here + How to read) byte-identical; extension is pure addition below | PASS (git diff: 0 lines removed) |
| 2 | `implementation-notes/` + `verification/` added (the two the quick map missed) | PASS |
| 3 | `verification/README.md` LINKED, untouched in place (ship-gate keys on it) | PASS |
| 4 | Spec enumeration via `lib/spec/spec-index.sh` pointer , NO per-file rows | PASS |
| 5 | NO unpinned counts anywhere in the map | PASS (grep: none) |
| 6 | Every relative link resolves | PASS (13/13) |
| 7 | Files stay put (no moves, no new per-dir READMEs) | PASS |
| 8 | test-meta green (proof-marker + spec-README pins unaffected) | PASS (661/661) |

## Confirmation run-table

| Case | Command | Expected | Observed |
|---|---|---|---|
| front-door verbatim | `git diff master -- docs/README.md \| grep '^-'` | no removed lines | none (pure addition) |
| link-check | resolve every `](path)` relative to docs/ | all exist | 13/13 OK |
| no counts | `awk '/full record/{f=1}f' docs/README.md \| grep -oE '[0-9]+ (specs\|files\|...)'` | none | none |
| verification link | `grep -q 'verification/README.md' docs/README.md` | match | match |
| spec-index pointer | `grep -q 'lib/spec/spec-index.sh' docs/README.md` | match | match |
| suite | `bash tests/test-meta.sh` | green | 661/661 |

## Run detail (2026-07-03)

```
$ git diff master -- docs/README.md | grep -E '^-' | grep -v '^---'
(empty)                          # front door byte-identical, extension is addition-only
# link-check: ../README.md, architecture.md, PHILOSOPHY.md, ABSORPTION.md, specs/, specs/README.md,
#   decisions/, implementation-notes/, verification/, verification/README.md, retro/, research/,
#   absorption/  -> all 13 resolve
$ bash tests/test-meta.sh -> 661/661 ; All meta tests passed.
```

## Reproduce

```bash
cd dwarves-kit
git diff master -- docs/README.md | grep -E '^-' | grep -v '^---'   # empty = front door verbatim
bash tests/test-meta.sh
```
