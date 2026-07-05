# Proof of done: board-mirror content-trust hardening

**Task**: close the runner-fastpath convergence-gate security finding (MAJOR): `board mirror`
copied `BACKLOG.md` Item/Notes verbatim into Hermes card title/body with no untrusted-content
marker and no stripping of the SG-04 `#queue{...}` routing token -- a stored prompt-injection
surface once any card-reading automation exists. Profile: security hardening of a shipped kit
tool. Branch: `fix/mirror-content-sanitize`. Date: 2026-07-05.

**Verdict: PASS** (green run below + a NEGATIVE CONTROL: neutering the disclaimer-prefix code
flips the NC7 marker assertion RED; restoring makes it green).

## Acceptance criteria

| # | Criterion | Met |
|---|---|---|
| A1 | The SG-04 `#queue{...}` token is stripped from the title + notes on BOTH paths (`extract-rows` AND `extract-megas`), before the row_hash and every downstream card use | yes |
| A2 | Every agent-visible field carries an untrusted marker: the full `MIRROR_UNTRUSTED_PREFIX` on every CREATE body + every CHANGE comment, the compact `MIRROR_UNTRUSTED_TITLE_TAG` on every title | yes |
| A3 | The row's own prose is RETAINED (labelled, never silently dropped) | yes |
| A4 | The `#queue{}` token reaches no card title, body, or comment on any path | yes |
| A5 | No regression: the pre-existing board-mirror assertions + the full kit suite stay green | yes |
| A6 | Negative control: reverting the body-prefix code makes the marker assertion fail | yes |

**Coverage note (why A1/A2 say "all paths"):** a fresh-context `kit:security-reviewer` adversarially
re-verified a body-only first cut and live-reproduced two gaps -- the CHANGE-op comment and the
`extract-megas` title were still unlabelled/unstripped. This fix is the completed all-paths version;
NC7b/NC7c pin the two paths the first cut missed.

## Implementation

Changes in `lib/board-mirror.sh` (+ a `## Content trust` section in SPEC-147):

- `MIRROR_UNTRUSTED_PREFIX` + `MIRROR_UNTRUSTED_TITLE_TAG` constants + `_strip_routing_tags` helper
  (portable BSD/GNU sed: `s/#queue{[^}]*}//g` + whitespace squeeze/trim).
- `extract_rows`: `item`/`notes` stripped before `_row_hash` + the TSV print.
- `extract_megas`: `title` stripped before `_row_hash` (its notes are machine-built `progress N/M`,
  no token possible).
- `cmd_plan` CREATE: `--arg title "${MIRROR_UNTRUSTED_TITLE_TAG}${item}"`, and the `--body` leads
  with `MIRROR_UNTRUSTED_PREFIX`.
- `cmd_plan` CHANGE: the `comment` reason leads with `MIRROR_UNTRUSTED_PREFIX`.

No-op on today's live data: the 16 already-mirrored cards are `extract-megas` `progress N/M` text
(no tokens), and no live BACKLOG row carries a token. This hardens the deferred full-`BACKLOG.md`
sync path. Existing cards are not re-synced -- the title tag / body marker are added at argv-build
time and do NOT alter row_hash, so a card picks up the labels only on its next create/content-change
(no re-sync storm).

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| A1-A4 | `bash tests/test-board-mirror.sh` (NC7 + NC7b + NC7c) | 13 security asserts pass | **13/13 PASS** |
| A5 | `bash tests/test-board-mirror.sh` | 72/72 (59 prior + 13 security) | **TOTAL 72 PASS 72 FAIL 0** |
| A5 | `bash tests/test-board.sh` | 45/45 | **45/45** |
| A5 | `bash tests/test-meta.sh` | 671/671 | **671/671** |
| A5 | `bats tests/test-queue.bats` | 14/14 | **14/14** |
| A5 | `shellcheck lib/board-mirror.sh` | clean | **rc=0, no findings** |
| A6 | revert body-prefix -> run NC7 | marker assert RED | **71/72, 1 FAIL (marker)** |

## Run detail (negative control = revert -> RED -> restore)

```
# GREEN (fix in place)
$ bash tests/test-board-mirror.sh | grep -E 'NC7|TOTAL'      # 13 security asserts (NC7/NC7b/NC7c)
  PASS NC7: ...strips the #queue{} token from the item / notes
  PASS NC7: the item's own PROSE is retained (labelled, never dropped)
  PASS NC7: the card BODY begins with the untrusted-content marker
  PASS NC7: the card TITLE carries the compact untrusted tag
  PASS NC7: the #queue{} token never reaches the card title / body
  PASS NC7: the injection prose survives into the card (labelled, not censored)
  PASS NC7b: the MEGAS-path title strips the #queue{} token / carries the untrusted tag
  PASS NC7c: a CHANGE is planned / the CHANGE comment carries the marker / strips the token
  TOTAL: 72   PASS: 72   FAIL: 0   SKIP: 0

# RED: neuter the CREATE body prefix (drop the "%s\n" + $MIRROR_UNTRUSTED_PREFIX from the body printf)
$ sed -i.bak "s/'%s\\\\norigin: %s/'origin: %s/" lib/board-mirror.sh
$ bash tests/test-board-mirror.sh | grep -E 'BODY begins|TOTAL'
  FAIL NC7: the card BODY begins with the untrusted-content marker
  TOTAL: 72   PASS: 71   FAIL: 1   SKIP: 0

# restore -> green again
$ mv -f lib/board-mirror.sh.bak lib/board-mirror.sh
$ bash tests/test-board-mirror.sh | grep -E 'TOTAL'
  TOTAL: 72   PASS: 72   FAIL: 0   SKIP: 0
```

The NC7 suite is two-sided by construction: the "token stripped" asserts fail if the strip does
nothing, and the "prose survives" asserts fail if the strip over-reaches and drops content -- so it
proves the fix labels-without-censoring. NC7b/NC7c extend that to the megas title and CHANGE comment
(the two paths a body-only first cut missed). The deliberate revert proves the marker assertion
specifically tracks the prefix code, not a vacuous pass.

## Reproduce

```
cd dwarves-kit                       # on branch fix/mirror-content-sanitize
bash tests/test-board-mirror.sh      # 72/72, 13 security asserts green
shellcheck lib/board-mirror.sh       # clean
# negative control:
sed -i.bak "s/'%s\\\\norigin: %s/'origin: %s/" lib/board-mirror.sh
bash tests/test-board-mirror.sh      # body-marker assert RED (71/72)
mv -f lib/board-mirror.sh.bak lib/board-mirror.sh
```

## Scope / what this is NOT

- NOT a full re-sync of the 16 live cards (unnecessary; they carry no untrusted content, and the
  labels are added at argv-build time so they do not change row_hash -- existing cards heal only on
  their next content change, no re-sync storm).
- The TITLE is now marked with a compact `[untrusted] ` tag (the first cut left it unmarked; the
  adversarial re-review argued -- correctly -- that the title is the most prominent field a naive
  dispatcher reads as "the task", so it must carry the strongest label, not the weakest). This does
  visibly tag every mirrored card title on the operator's own cockpit; a shorter/removable marker is
  a trivial follow-up if that proves noisy in daily use.
- NOT the two Minor findings from the same review (`--remote-kit-path` argv-safety + the
  `--snapshot`-path collision) -- those are separate, lower-severity follow-ups routed to NOTES.
