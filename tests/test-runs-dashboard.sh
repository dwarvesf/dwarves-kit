#!/usr/bin/env bash
# test-runs-dashboard.sh -- `mega runs` (SPEC-215): the estate runs dashboard generator.
#
# Pins the scanner's parse contract and the empty-state path over a fixture estate built in a
# mktemp sandbox (no real repo is ever read, no network, no gh):
#   1.  Title/date come from the document; a document with no `# ` heading falls back to a
#       path-derived title, never an empty one.
#   2.  Status is a read of the document's prose: `MET` classifies green, `HELD` classifies
#       attention EVEN when a green word appears earlier in the same document.
#   3.  Captures: an existing PNG embeds as a `data:` URI; a MISSING reference contributes
#       nothing (no broken <img>); an `.mp4` renders as a link, never base64; a capture over
#       the per-image cap degrades to a labelled link.
#   4.  Receipts: a PR number and a merge SHA both surface on the card.
#   5.  EMPTY-STATE NC: an empty root, and a root that does not exist, each render a VALID page
#       carrying the empty-state banner with ZERO cards and exit 0 -- never a crash, never a
#       fabricated card.
#   6.  Registry: rows without the third `bridge` column are still scanned (bridge gates a write
#       path, not a read); a row whose BACKLOG.md is missing is skipped, and its SIBLING rows
#       still render.
#   7.  Self-containment: the rendered page carries no external asset URL in any `src=`.
#   8.  Dedup: one repo registered twice under two names produces its cards ONCE.
#
# Run: bash tests/test-runs-dashboard.sh   (exit 0 = all AC/NC green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GEN="$KIT_DIR/lib/mega/runs-dashboard.py"
MEGA="$KIT_DIR/lib/mega/mega.sh"

PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dk-runs-dash-test.XXXXXX")"
TMP="$(cd "$TMP" && pwd)"
trap 'rm -rf "$TMP"' EXIT

# ---- fixture estate ---------------------------------------------------------------------------
REPO="$TMP/repo-alpha"
mkdir -p "$REPO/_meta/megagoals/_archive/demo-mega" \
         "$REPO/tools/widget/docs/shots" \
         "$REPO/docs/verification/thing/runs" \
         "$REPO/docs/verification"

# A tiny REAL png (1x1, ~70 bytes) so the embed path exercises actual base64, not a stub string.
python3 - "$REPO/tools/widget/docs/shots/demo.png" <<'PY'
import base64, sys
open(sys.argv[1], "wb").write(base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="))
PY
# An over-cap capture: 40 KB of zeros, tested against --max-embed-bytes 1024.
python3 -c "open('$REPO/tools/widget/docs/shots/big.png','wb').write(b'\x89PNG\r\n\x1a\n'+b'\0'*40000)"
: > "$REPO/tools/widget/docs/shots/clip.mp4"

cat > "$REPO/_meta/megagoals/_archive/demo-mega/RUN_REPORT.md" <<'MD'
# RUN REPORT , demo mega

**Ran:** 2026-03-04 (one operator)
**Outcome:** MET on every sub-goal, though PR #4242 is still HELD for review.
Merged at 9f8e7d6c5b4a as the final commit.
MD

cat > "$REPO/tools/widget/docs/proof-of-done.md" <<'MD'
# Proof of done - widget

Ran 2026-05-06. All checks PASSED.

![working demo](shots/demo.png)
![absent capture](shots/nope.png)
![screen recording](shots/clip.mp4)
![too large](shots/big.png)
MD

# No `# ` heading anywhere: the path-derived title fallback must fire.
cat > "$REPO/docs/verification/thing/runs/2026-06-07-0900.md" <<'MD'
Command: bash tests/test-thing.sh
Exit: 0
Everything PASSED.
MD

# The FLAT `docs/verification/<slug>.md` shape the verification README still accepts.
cat > "$REPO/docs/verification/flatproof.md" <<'MD'
# Flat proof

2026-07-08 run. Outcome MET.
MD

# Never a run artifact: these two must NOT become cards.
echo "# readme" > "$REPO/docs/verification/README.md"
echo "# design" > "$REPO/docs/verification/test-design.md"

echo "| ID-1 | x | y | queued |" > "$REPO/_meta/BACKLOG.md"

EMPTY="$TMP/repo-empty"; mkdir -p "$EMPTY"
GONE="$TMP/repo-does-not-exist"

# `grep -c` PRINTS 0 and EXITS 1 when there is no match, so a `|| echo 0` fallback would emit
# a second 0. Swallow the exit code instead and let grep's own count stand.
card_count() { grep -c 'class="card ' "$1" 2>/dev/null; true; }

# ---- AC 1-4: parse contract over the fixture repo ----------------------------------------------
OUT="$TMP/alpha.html"
if python3 "$GEN" --root "$REPO" --out "$OUT" --max-embed-bytes 1024 >/dev/null 2>"$TMP/err1"; then
  ok "generator exits 0 over a fixture repo"
else
  no "generator exits 0 over a fixture repo (stderr: $(cat "$TMP/err1"))"
fi

N="$(card_count "$OUT")"
[ "$N" -eq 4 ] \
  && ok "exactly the 4 real artifacts become cards (README + test-design excluded), got $N" \
  || no "expected 4 cards (run report, proof-of-done, verification run, flat proof), got $N"

grep -q 'RUN REPORT , demo mega' "$OUT" \
  && ok "title comes from the document's own # heading" \
  || no "title not taken from the # heading"

grep -q '2026-03-04' "$OUT" \
  && ok "date parsed from the document body" \
  || no "date not parsed from the document body"

# The headingless verification run must still carry a non-empty, path-derived title.
grep -q '<h3>thing<span' "$OUT" \
  && ok "headingless document falls back to a path-derived title" \
  || no "headingless document has no path-derived title fallback"

# `MET` appears BEFORE `HELD` in the run report: attention must still win.
grep -q '>ATTENTION<' "$OUT" \
  && ok "HELD classifies ATTENTION even with an earlier green word" \
  || no "HELD did not classify ATTENTION"

grep -q '>GREEN<' "$OUT" \
  && ok "a PASSED/MET document classifies GREEN" \
  || no "no GREEN card rendered"

grep -q 'src="data:image/png;base64,' "$OUT" \
  && ok "an existing PNG embeds as a data: URI" \
  || no "existing PNG did not embed as a data: URI"

grep -q 'nope.png' "$OUT" \
  && no "a MISSING capture reference leaked into the page" \
  || ok "a missing capture reference contributes nothing (no broken img)"

grep -q 'video: <a' "$OUT" \
  && ok "an .mp4 renders as a link, never base64" \
  || no ".mp4 did not render as a link"

grep -q 'over embed budget' "$OUT" \
  && ok "an over-cap capture degrades to a labelled link" \
  || no "over-cap capture did not degrade to a labelled link"

grep -q 'PR #4242' "$OUT" \
  && ok "a PR number surfaces as a receipt" \
  || no "PR number did not surface as a receipt"

grep -q 'sha 9f8e7d6c5b4a' "$OUT" \
  && ok "a merge SHA surfaces as a receipt" \
  || no "merge SHA did not surface as a receipt"

# ---- AC 7: self-containment --------------------------------------------------------------------
if grep -o 'src="[^"]*"' "$OUT" | grep -qv '^src="data:'; then
  no "page carries an external asset URL in a src= slot"
else
  ok "page is self-contained (every src= is a data: URI)"
fi

# ---- NC 5: empty state -------------------------------------------------------------------------
for label in empty missing; do
  case "$label" in
    empty)   ROOT="$EMPTY" ;;
    missing) ROOT="$GONE" ;;
  esac
  EOUT="$TMP/$label.html"
  if python3 "$GEN" --root "$ROOT" --out "$EOUT" >/dev/null 2>"$TMP/err-$label"; then
    if grep -q 'no run artifacts' "$EOUT" && [ "$(card_count "$EOUT")" -eq 0 ] \
       && grep -q '</html>' "$EOUT"; then
      ok "NC: a $label root renders a valid empty-state page, 0 cards, exit 0"
    else
      no "NC: a $label root did not render the empty-state banner with 0 cards"
    fi
  else
    no "NC: a $label root did not exit 0 (stderr: $(cat "$TMP/err-$label"))"
  fi
done

# ---- AC 6: registry -----------------------------------------------------------------------------
REG="$TMP/boards.txt"
cat > "$REG" <<EOF
# comment line, ignored
alpha    $REPO/_meta/BACKLOG.md
ghostrepo $TMP/nowhere/BACKLOG.md
EOF
ROUT="$TMP/reg.html"
if python3 "$GEN" --registry "$REG" --out "$ROUT" >/dev/null 2>"$TMP/err-reg"; then
  [ "$(card_count "$ROUT")" -eq 4 ] \
    && ok "registry rows WITHOUT a bridge column are still scanned" \
    || no "registry row without a bridge column was not scanned (cards: $(card_count "$ROUT"))"
  grep -q 'ghostrepo' "$TMP/err-reg" \
    && ok "a registry row with a missing BACKLOG.md is skipped with a stderr note" \
    || no "missing-BACKLOG.md row produced no stderr note"
else
  no "registry scan did not exit 0 (stderr: $(cat "$TMP/err-reg"))"
fi

# ---- AC 8: dedup ---------------------------------------------------------------------------------
DOUT="$TMP/dedup.html"
python3 "$GEN" --root "$REPO" --root "$REPO/." --out "$DOUT" >/dev/null 2>&1
[ "$(card_count "$DOUT")" -eq 4 ] \
  && ok "a root registered twice produces its cards once" \
  || no "double-registered root duplicated cards (got $(card_count "$DOUT"))"

# ---- the verb is reachable through the subsystem entry -------------------------------------------
VOUT="$TMP/verb.html"
if bash "$MEGA" runs --root "$REPO" --out "$VOUT" >/dev/null 2>"$TMP/err-verb"; then
  [ "$(card_count "$VOUT")" -eq 4 ] \
    && ok "\`mega runs\` reaches the generator with flags intact" \
    || no "\`mega runs\` rendered an unexpected card count"
else
  no "\`mega runs\` did not exit 0 (stderr: $(cat "$TMP/err-verb"))"
fi

bash "$MEGA" --help 2>/dev/null | grep -q 'mega.sh runs' \
  && ok "the runs verb is documented in \`mega --help\`" \
  || no "the runs verb is missing from \`mega --help\`"

echo
echo "passed: $PASS   failed: $FAIL"
[ "$FAIL" -eq 0 ]
