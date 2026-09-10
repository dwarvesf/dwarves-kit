# repo-hygiene detector 3: mega-goal completion precision, recorded runs

Run id: `det3-completion-precision`. Lane: normal. Module: `lib/repohygiene/`.
Full record, including the measured before and after on the real case, the adversarial review
findings, and the full mutation battery: `lib/repohygiene/docs/proof-of-done.md` sections 7 and
8 (co-located with the module, per SPEC-016). This file is the ship-gate's recorded run and
rollback note.

## Recorded runs

| # | Command | Exit | Result |
|---|---|---|---|
| 1 | `bash tests/test-repohygiene.sh` | 0 | 82/82 passed, 0 failed. Verdict: PASS |
| 2 | `bash tests/test-meta.sh` | 0 | Passed: 844 / 844, all meta tests passed. Verdict: PASS |
| 3 | `bash tests/test-kit-contract.sh` | 0 | 25 passed, 0 failed. Verdict: PASS |

## Live run of the primary flow

The primary flow is the scanner against a real repo. Recorded against `ops-toolkit` frozen at
`7be6151f`, in a detached worktree. That is the tree the loop's first live run saw, one commit
before the co-location PR that moved two of the five mega-goals it flagged, so the defect is
present to measure.

```
Command: bash lib/repohygiene/repohygiene.sh scan \
           --repo <ops-toolkit@7be6151f> --detectors 3
Exit:    0
Before:  6 findings. Five mega-goal rows (hermes-multiplex-followups, icy-ops-enhancements,
         mochi-icy-simplify, vibe-dex-saas, vibe-dex-showcase), each claiming a closed
         mega-goal on the strength of a commit subject. A human read each folder's own ROADMAP
         and found only TWO were finished, so three of the five were false positives. Plus one
         unrelated file row for docs/briefs/CONTEXT.md.
After:   2 findings. One mega-goal row (cluster-notify-wiring, whose own roadmap declares
         "## Status 2026-09-01: all four goals SHIPPED"), refusing the move for a stated
         reason: the folder carries no checked checklist item, so nothing in it positively
         records a finished sub-goal. Plus the same unchanged CONTEXT.md row, which is the
         negative half of the measurement: detector 3's FILE path did not move.
Verdict: PASS. Three false positives gone, zero introduced.
```

The same command against the current `ops-toolkit` tree (`1139120a`) returns the identical two
findings. Per-line attribution of which absences belong to this fix and which to the
co-location PR is in the proof of done section 7.

## Negative control

Sixteen controls, one per rule the docs claim, each a single-line edit to
`lib/repohygiene/repohygiene.sh`, restored from a backup copy after each run. Full transcripts
in the proof of done sections 7 and 8.

```
Command: bash tests/test-repohygiene.sh, after breaking the open-item gate
Exit:    1
Result:  74/82 passed, 8 failed. The three real misreads all came back, plus the
         non-markdown, numbered and blockquoted checklist cases.
Verdict: RED, as intended

Command: bash tests/test-repohygiene.sh, after promoting the commit-evidence verdict to FIX
Exit:    1
Result:  80/82 passed, 2 failed
Verdict: RED, as intended

Command: bash tests/test-repohygiene.sh, after handing git a globbing pathspec
Exit:    1
Result:  81/82 passed, 1 failed (a file named like a glob is judged on its own history alone)
Verdict: RED, as intended

Command: bash tests/test-repohygiene.sh, after letting a glob-named folder reach a FIX
Exit:    1
Result:  81/82 passed, 1 failed
Verdict: RED, as intended

Command: bash tests/test-repohygiene.sh, after dropping the checked-item requirement
Exit:    1
Result:  81/82 passed, 1 failed
Verdict: RED, as intended

Command: bash tests/test-repohygiene.sh, restored
Exit:    0
Result:  82/82 passed, 0 failed
Verdict: PASS, green again
```

The remaining eleven controls (the checkbox anchor, the text-not-path keyword test, open-marker
precedence, the extension set, the numbered and blockquoted forms, symlink exclusion,
marker-prose exclusion, the residue guard, the top-level-only marker scan, the `State:` form,
and the owner-majority gate on a folder) each turn the suite red on the assertion that names
them. All sixteen bite.

## Rollback

Revert the branch. The change is confined to `lib/repohygiene/repohygiene.sh` plus its docs and
tests; nothing is deployed, no state is written, and the scanner never writes to a target repo.
Reverting restores the previous detector-3 behavior, which over-reports closed mega-goals
rather than under-reporting them, so a rollback loses precision without losing safety on any
verdict the operator has already applied.
