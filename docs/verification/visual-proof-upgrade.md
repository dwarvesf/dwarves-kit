# Visual proof upgrade: integration proof

SPEC-385, opt-in behind `[proof] visual`. The four task proofs (`visual-proof-t1.md` to `t4.md`) cover each part; this file covers the merged branch against the real R2 bucket.

## Green run: a UI change against the real bucket

```
Command: e2e-visual.sh <kit worktree>   (fresh repo, visual on, src/settings.tsx changed)
Exit: 0
Output:
== 1. UI diff, text-only proof
rc=1
BLOCKED: visual proof of done. The branch changes UI files; its proof needs one qualifying image:
  no image: no committed image link, no verified uploaded asset, no cached local asset.
== 2. put -> ![settings-desktop](https://proof.han.ws/tieubao/kit-proof-smoke/settings-page/fec51670ba2b1390ec1163f388a2d190/settings-desktop.webp)
== 3. UI diff, uploaded image
rc=0
== 4. tamper: manifest sha changed
rc=1
BLOCKED: visual proof of done. The branch changes UI files; its proof needs one qualifying image:
Verdict: PASS
```

## Green run: offline capture, then flush

```
Command: e2e-offline.sh <kit worktree>   (put with a failing uploader, commit, flush with the real uploader)
Exit: 0
Output:
== 1. put while offline
rc=0 line=![profile-desktop](https://proof.han.ws/tieubao/kit-proof-smoke/profile/99a20d9d9f9335f69fbd27c0f07a539c/profile-desktop-d7ff8cdd.webp)
   stderr: queued: profile/profile-desktop (upload failed or offline); run bin/proof-asset flush
== 2. gate while still unuploaded
rc=1
  fetch failed: https://proof.han.ws/tieubao/kit-proof-smoke/profile/99a20d9d9f9335f69fbd27c0f07a539c/profile-desktop-d7ff8cdd.webp
== 3. flush online (real wrangler uploader)
flush rc=0
== 4. gate after flush (after the cache-busting fetch fix)
rc=0
Verdict: PASS
```

The uploaded image from the live CLI run renders here: ![gradient test image](https://proof.han.ws/tieubao/kit-proof-smoke/live-smoke/2d473a73b87b39ce91551df9dd6b6d60/gradient.webp) (a synthetic test image; it expires 90 days after upload).

## Green run: the affected suites

```
Command: bash tests/<suite>.sh, each run from the branch
Exit: 0
Output:
test-proof-asset: ALL PASS
test-proof-visual-gate: all 31 passed
test-proof-contract-visual: ALL PASS (5/5)
test-wrap-land: all 489 passed
test-proof-captured-output: all 44 passed
test-ship-gate-fail-closed: PASS=7 FAIL=0
test-adopt: PASS=54 FAIL=0
Verdict: PASS
```

## NEGATIVE CONTROL

The same text-only UI change (a `.css` file, visual on), checked by master's gate from a fresh clone and by this branch's gate:

```
Command: lib/gate/proof-ledger.sh check <repo> <base> a   (master clone, then the branch)
Exit: 0 on master, 1 on the branch
Output:
master gate: rc=0
branch gate: rc=1
BLOCKED: visual proof of done. The branch changes UI files; its proof needs one qualifying image:
  no image: no committed image link, no verified uploaded asset, no cached local asset.
Result: RED as expected
```

The security reviewer's exploit (a manifest whose `file` is `../../../../outside.txt`) re-run against the branch: `flush: x: manifest slug/rand/assets invalid; queue left pending`, and no upload call.

## Test plan coverage

| Spec rows | Run |
|---|---|
| 1 to 12 | `tests/test-proof-visual-gate.sh`, one labelled case each (31 checks after fix round 1) |
| 13 to 20 | `tests/test-proof-asset.sh` |
| 21, 22 | `tests/test-proof-contract-visual.sh` |
| 23 to 25 | `tests/test-wrap-land.sh`, section `sec_flush`, plus the real offline round trip test added in fix round 1 |
| T0 | the live smoke above: public GET 200 with matching bytes on both domains, 90-day rule read back |

## Battery

| Leg | Model | Verdict | Caught |
|---|---|---|---|
| Acceptance verifier | Opus | PASS | 25 of 25 cases covered; override path question |
| Security | Opus | FIX THEN SHIP | HIGH: a manifest could upload any local file; 4 MEDIUM |
| Correctness | Opus | FIX THEN SHIP | HIGH: flush dirtied the tree; cache not gitignored in other repos |
| Advisor | Opus | 6 findings | image never shown in the reply; Discord path; local mode broken link |

Fix round 1 (Devin) and the lead patch addressed every finding; the suites above are the re-run.

## Not proven

- The Mini cannot upload: its wrangler has no login and no R2 token exists in 1Password. Captures made there queue until a flush runs on the Air.
- A PR image fetched before its upload can show broken for up to 4 hours (edge-cached 404). The gate is immune; GitHub's fetch is not.
- No consumer repo has `visual = true` yet; the first real UI PR is the first live use.

Verdict: PASS
