# Proof of done: board lint

`board lint` (backlog.sh `lint` verb): enumerates board rows the bash parser
and the git-to-Hermes sync misread, before they surface as sync failures or
renderer UNRECOGNIZED warnings. Enumerator contract per `lib/lint/`'s
precedent: prints findings, exits 0.

## Green run

```
Command: bash tests/test-board-lint.sh
Exit: 0
Verdict: PASS - 10/10 cases: clean board silent, duplicate ids with both line
         numbers, extra cell count, `\|` inside a status cell, unrecognized
         status, non-id first cell, divider rows and mid-row escapes and
         non-board tables ignored, missing file refuses rc=1
```

```
Command: bash lib/board/backlog.sh lint _meta/BACKLOG.md
Exit: 0
Verdict: PASS - (no lint findings) on the kit's own board after the ID-923/880/
         886 dedupe and the ID-021/420/445 &#124; normalization
```

```
Command: bash tests/test-meta.sh
Exit: 0
Verdict: PASS - 854/854 including the FEATURES.md freshness pin, regenerated
         in this branch (it had drifted on master before this change)
```

## Negative control

```
Command: neuter the duplicate-id END rule (seen[id] > 1 -> 0), then
         bash tests/test-board-lint.sh
Exit: 1
Verdict: PASS - the duplicate-id case flips RED; rule restored, suite green
```

## Rules pinned

- cell-count counts UNESCAPED pipes only; a mid-row `\|` is legal to the sync
  parser and leaves the status cell readable positionally, so it is not a
  finding.
- escaped-pipe fires only when `\|` sits inside the status cell (the read that
  produced renderer UNRECOGNIZED warnings on ID-021/420/445).
- divider rows (`| **I1 -- ...** | | | |`) are a board layout convention and
  are skipped.
