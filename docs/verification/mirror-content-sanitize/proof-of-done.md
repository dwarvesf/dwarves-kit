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
| A1 | The SG-04 `#queue{...}` token is stripped from item AND notes in `extract-rows`, before the row_hash and every downstream card use | yes |
| A2 | Every synthesized card BODY is prefixed with the fixed `MIRROR_UNTRUSTED_PREFIX` marker | yes |
| A3 | The row's own prose is RETAINED (labelled, never silently dropped) | yes |
| A4 | The `#queue{}` token reaches neither the card title nor the card body | yes |
| A5 | No regression: the pre-existing 59 board-mirror assertions + the full kit suite stay green | yes |
| A6 | Negative control: reverting the prefix code makes the marker assertion fail | yes |

## Implementation

Three surgical changes in `lib/board-mirror.sh` (+ a `## Content trust` section in SPEC-147):

- `MIRROR_UNTRUSTED_PREFIX` constant + `_strip_routing_tags` helper (portable BSD/GNU sed:
  `s/#queue{[^}]*}//g` + whitespace squeeze/trim).
- `extract_rows`: `item`/`notes` are run through `_strip_routing_tags` before `_row_hash` and the
  TSV print, so the token is gone from title, body, AND the CHANGE-op comment, and the hash keys
  off the real content.
- `cmd_plan` CREATE branch: the card `--body` is now built as
  `printf '%s\norigin: ...\nnotes: ...\nsynced: ...' "$MIRROR_UNTRUSTED_PREFIX" ...`.

No-op on today's live data: the 16 already-mirrored cards come from `extract-megas` (auto-generated
`progress N/M` text, no `#queue{}` tokens), and no live BACKLOG row carries such a token. This
hardens the deferred full-`BACKLOG.md` sync path. Existing cards are not re-synced (the body change
does not alter row_hash; a card only picks up the marker on its next create/content-change).

## Confirmation run-table

| Check | Command | Expected | Result |
|---|---|---|---|
| A1-A4 | `bash tests/test-board-mirror.sh` (NC7 block) | 7 NC7 asserts pass | **7/7 PASS** |
| A5 | `bash tests/test-board-mirror.sh` | 66/66 (59 prior + 7 NC7) | **TOTAL 66 PASS 66 FAIL 0** |
| A5 | `bash tests/test-board.sh` | 45/45 | **45/45** |
| A5 | `bash tests/test-meta.sh` | 671/671 | **671/671** |
| A5 | `bats tests/test-queue.bats` | 14/14 | **14/14** |
| A5 | `shellcheck lib/board-mirror.sh` | clean | **rc=0, no findings** |
| A6 | revert prefix -> run NC7 | marker assert RED | **65/66, 1 FAIL (marker)** |

## Run detail (negative control = revert -> RED -> restore)

```
# GREEN (fix in place)
$ bash tests/test-board-mirror.sh | grep -E 'NC7|TOTAL'
  PASS NC7: extract-rows strips the #queue{} token from the item
  PASS NC7: extract-rows strips the #queue{} token from the notes
  PASS NC7: the item's own PROSE is retained (labelled, never dropped)
  PASS NC7: the card BODY begins with the untrusted-content marker
  PASS NC7: the #queue{} token never reaches the card title
  PASS NC7: the #queue{} token never reaches the card body
  PASS NC7: the injection prose survives into the card (labelled, not censored)
  TOTAL: 66   PASS: 66   FAIL: 0   SKIP: 0

# RED: neuter the disclaimer prefix (drop the "%s\n" + $MIRROR_UNTRUSTED_PREFIX from the body printf)
$ sed -i.bak "s/'%s\\\\norigin: %s/'origin: %s/" lib/board-mirror.sh
$ bash tests/test-board-mirror.sh | grep -E 'BODY begins|TOTAL'
  FAIL NC7: the card BODY begins with the untrusted-content marker
  TOTAL: 66   PASS: 65   FAIL: 1   SKIP: 0

# restore -> green again
$ mv -f lib/board-mirror.sh.bak lib/board-mirror.sh
$ bash tests/test-board-mirror.sh | grep -E 'BODY begins|TOTAL'
  PASS NC7: the card BODY begins with the untrusted-content marker
  TOTAL: 66   PASS: 66   FAIL: 0   SKIP: 0
```

The NC7 suite is two-sided by construction: the "token stripped" asserts fail if the strip does
nothing, and the "prose survives" asserts fail if the strip over-reaches and drops content -- so a
single self-contained block proves the fix labels-without-censoring. The deliberate revert above
proves the marker assertion specifically tracks the prefix code, not a vacuous pass.

## Reproduce

```
cd dwarves-kit                       # on branch fix/mirror-content-sanitize
bash tests/test-board-mirror.sh      # 66/66, NC7 = 7 green
shellcheck lib/board-mirror.sh       # clean
# negative control:
sed -i.bak "s/'%s\\\\norigin: %s/'origin: %s/" lib/board-mirror.sh
bash tests/test-board-mirror.sh      # NC7 marker assert RED
mv -f lib/board-mirror.sh.bak lib/board-mirror.sh
```

## Scope / what this is NOT

- NOT a full re-sync of the 16 live cards (unnecessary; they carry no untrusted content).
- NOT title-prefixing (the review asked for body-labelling + token-strip; titles are token-stripped
  but keep their content unmarked, since a body-reading agent sees the body marker). A title marker
  is a possible later hardening, noted in NOTES, not built here.
- NOT the two Minor findings from the same review (`--remote-kit-path` argv-safety + the
  `--snapshot`-path collision) -- those are separate, lower-severity follow-ups routed to NOTES.
