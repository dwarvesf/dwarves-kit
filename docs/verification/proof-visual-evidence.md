# Verification , proof-of-done accepts screenshot/GIF evidence

**Change:** `lib/proof-ledger.sh` now accepts a committed screenshot/GIF embed
(`![...](*.png|gif|jpe?g|svg|webp)`) as the "captured run" half of the proof, alongside the
text run-table (`Command:`/`Exit:`/`Verdict: PASS`). The semantic marker (NEGATIVE CONTROL /
rollback) is still required; this only widens "it ran" from text-only to {text OR picture}.
README documents it; the blocked-message names the option.

## Confirmation run-table

| Check | Command | Exit | Result |
|---|---|---|---|
| syntax | `bash -n lib/proof-ledger.sh` | 0 | OK |
| existing proof tests | `bash tests/test-proof-dir-layout.sh` | 0 | ALL PASS (3/3), set-wise still load-bearing |
| accepts image | behavioral file with `NEGATIVE CONTROL` + `![demo](x.gif)` and NO Exit/PASS | - | PASS (image accepted) |

Command: `bash tests/test-proof-dir-layout.sh`
Exit: 0

## NEGATIVE CONTROL

A behavioral proof file with `NEGATIVE CONTROL` but **neither** a text run-table **nor** an image
embed is still BLOCKED (verified: prints `BLOCK (correct)`). So the widening did not make the gate
pass-anything , it accepts a picture OR a run-table, but still requires one of them plus the
semantic marker. Removing the `|| grep img_re` addition makes the image case revert to BLOCKED
(the prior text-only behavior), confirming the new clause is load-bearing.

## Reproduce
```
img_re='!\[[^]]*\]\([^)]*\.(png|gif|jpe?g|svg|webp)\)'
printf '## NEGATIVE CONTROL\n![demo](x.gif)\n' > /tmp/p.md
grep -qi 'NEGATIVE CONTROL' /tmp/p.md && { grep -qE 'Exit:[[:space:]]*0|PASS' /tmp/p.md || grep -qiE "$img_re" /tmp/p.md; } && echo PASS || echo BLOCK
bash tests/test-proof-dir-layout.sh
```

## Follow-up hardening (review fix #1 + test #2)

Review found the embed was matched by STRING only: a dangling `![x](missing.gif)` (a file that does
not exist) passed the gate, contradicting the "committed screenshot/GIF" intent and re-opening the
fabrication surface the gate exists to close. Fixed: a new `_has_committed_image` helper resolves each
embedded image path (relative to the proof file's dir, then the repo root) and the image branch now
requires the file to actually EXIST. Wired into all four sites (per-file + set-wise, behavioral +
stateful). A real committed image still passes; a dangling reference now BLOCKS.

Automated regression test added (`tests/test-proof-visual-evidence.sh`, wired into CI), so the path is
guarded, not just manually reproduced:

| Case | Evidence | Expected | Result |
|---|---|---|---|
| real image | `![demo](vf-vis-demo.gif)` + the committed .gif | ACCEPT | PASS |
| dangling image | `![demo](vf-vis-missing.gif)`, no file | **BLOCK (fix #1)** | PASS |
| text run-table | `Command:`/`Exit: 0`/`Verdict: PASS` | ACCEPT (regression) | PASS |
| no evidence | marker only | BLOCK | PASS |

```
Command: bash tests/test-proof-visual-evidence.sh
Exit: 0
Verdict: PASS (ALL PASS 4/4)
```
Regression: `bash tests/test-proof-dir-layout.sh` still 3/3; `bash tests/test-meta.sh` 500/500.

## NEGATIVE CONTROL (fix #1)

Reverting `_has_committed_image` (making the image branch string-only again) flips the `dangling image`
case in `tests/test-proof-visual-evidence.sh` from BLOCK back to ACCEPT , the test goes RED, confirming
the hardening is load-bearing.

## Rollback

Pure additive widening of two grep conditions (per-file + set-wise, both classes) + the
`_has_committed_image` existence guard + doc text. `git revert <sha>` restores text-only evidence. No
schema/state; the gate stays strictly tighter-or-equal for any existing text-run-table proof.
