# Proof of done: runs-dashboard

Spec: `docs/specs/SPEC-215-runs-dashboard.md`. Lane normal, type spec-feature, class behavioral.
Branch `feat/runs-dashboard`. Run recorded 2026-07-31, after rebase onto `origin/master` at `2dbdb5a`.

The primary flow is the real one, not a proxy: the generator runs over the LIVE estate through
the `bin/mega runs` entry a consumer would type.

## Acceptance criteria

| # | Criterion | Where verified |
|---|---|---|
| 1 | Generator runs over the real estate and produces an HTML file with at least one card built from an existing artifact | run-table rows 1 and 2 below |
| 2 | An empty root yields a valid empty-state page, not a crash | run-table row 3 (negative control A) |
| 3 | Scanner parse contract holds: title, date, status, captures, receipts | `tests/test-runs-dashboard.sh` rows 1-13 |
| 4 | The page is self-contained: no external asset URL | `tests/test-runs-dashboard.sh` self-containment check |
| 5 | Registry rows without a `bridge` column are still scanned; a missing BACKLOG.md is skipped without aborting | `tests/test-runs-dashboard.sh` registry checks |
| 6 | The verb is reachable as `mega runs` and documented in `mega --help` | `tests/test-runs-dashboard.sh` final two checks |
| 7 | No regression in the module this build imports from | run-table row 6 |

## Confirmation run-table (2026-07-31, this branch)

| # | Check | Command | Result |
|---|---|---|---|
| 1 | Live estate render | `bash bin/mega runs --registry ~/workspace/tieubao/ops-toolkit/_meta/boards.txt --out /tmp/rd-estate.html` | Exit 0. **492 cards across 7 repos**, 42 images embedded, 1 honest over-budget fallback, 11 MB, 0.4s wall |
| 2 | Single-repo render (this repo) | `bash bin/mega runs --root . --out /tmp/rd-real.html && grep -c 'class="card ' /tmp/rd-real.html` | Exit 0, prints **205** |
| 3 | Negative control A, empty root | `bash bin/mega runs --root "$(mktemp -d)" --out /tmp/rd-empty.html && grep -c 'no run artifacts' /tmp/rd-empty.html` | Exit 0, prints **1**; card count **0** |
| 4 | Negative control B, revert | `mv lib/mega/runs-dashboard.py /tmp/ && bash tests/test-runs-dashboard.sh` | **RED: passed 3, failed 17** |
| 5 | Restore after revert | `mv /tmp/runs-dashboard.py lib/mega/ && bash tests/test-runs-dashboard.sh` | **GREEN: passed 21, failed 0**; `git status --porcelain` empty |
| 6 | Regression, the imported module | `bash tests/test-mega-review.sh` | **26 passed, 0 failed** |
| 7 | Regression, the owning subsystem | `bash tests/test-mega.sh` | **PASS=16 FAIL=0** |

## Negative controls

Two, because the spec's own acceptance names a boundary case and the gate contract names a revert case.

**A. Empty input.** Pointing the generator at an empty temp directory renders a valid page carrying
the empty-state banner with zero cards and exits 0. It does not crash and it does not fabricate a
card to fill the page. Recorded as row 3.

**B. Revert to RED, restore to green.** Removing `lib/mega/runs-dashboard.py` and re-running the
suite drops it from 21 passing to **3 passing, 17 failing**, so the suite is genuinely coupled to
the code under test rather than trivially green. Restoring the file returns it to 21/21 with a
clean working tree. Recorded as rows 4 and 5. Verbatim failure line from the RED run:

```
NOT ok - `mega runs` did not exit 0 (stderr: python3: can't open file
'.../lib/mega/runs-dashboard.py': [Errno 2] No such file or directory)

passed: 3   failed: 17
```

The 3 checks that still pass under revert are the ones that legitimately do not touch the
generator: the empty-state stderr note, the missing-BACKLOG registry note, and the `mega --help`
documentation check.

## Reproducible

Every command above is re-runnable from the repo root with no arguments beyond what is shown, no
network, and no credentials. `tests/test-runs-dashboard.sh` builds its own fixture estate in a
`mktemp -d` sandbox and removes it on exit, so it reads no real repo and leaves nothing behind.
The two live-estate rows read only, write only their `--out` path, and cache nothing.

## What this proof does NOT cover

Stated plainly rather than implied.

- **Visual quality of the rendered page is unverified.** The checks confirm the page is
  well-formed, self-contained, carries the expected card count, and embeds real base64 image
  data. Nobody has looked at it. Layout, contrast, and thumbnail legibility are unconfirmed.
  This is exactly the gap the visual-first contract added in `docs/verification/README.md` exists
  to close, and it closes for this feature once the visual-proof module (kit board ID-395) lands
  and a capture of the dashboard can be embedded here.
- **Status classification is a prose heuristic**, not a ledger fact. It is pinned against fixtures
  where a green word precedes an attention word, but a document phrased unusually can still be
  misread. Every card links its source document so a human can confirm in one click.
- **Pre-existing unrelated failure:** `tests/test-bin-forwarders.sh` fails one check because its
  `bin/` census omits `activate` and `release`, both present on master. This branch adds no `bin/`
  entry and `git diff master -- bin/` is empty, so the failure is not caused here and is left
  alone per the surgical-changes rule.
