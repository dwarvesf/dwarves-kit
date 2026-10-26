#!/usr/bin/env bash
# test-doc-figures.sh -- lib/system-design/doc-figures keeps docs/figures honest: check passes on the
# committed state, and fails on an edited sheet with no re-render, a missing PNG, a manifest entry
# with no sheet, and a doc reference to an unknown figure id. Every mutation runs on a temp copy.
# render (browser needed) runs only when node and Chrome or Edge are present.
#
# Run: bash tests/test-doc-figures.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DF="$KIT_DIR/lib/system-design/doc-figures"
FIG="$KIT_DIR/docs/figures"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
chk() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-docfig-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMPD"' EXIT

# fresh <name>: a temp root holding a copy of the committed figures and a README that cites one.
fresh() {
  local r="$TMPD/$1"
  mkdir -p "$r/docs/figures" "$r/docs/guides"
  cp "$FIG"/MODEL.md "$FIG"/MANIFEST.tsv "$FIG"/*.png "$r/docs/figures/"
  printf '# Test\n\n![loop](docs/figures/loop.png)\n' > "$r/README.md"
  printf '# Guide\n\n![v](../figures/v-model.png)\n' > "$r/docs/guides/g.md"
  printf '%s' "$r"
}
# run <root>: check against that root; sets OUT and RC.
run() { OUT=$(DOC_FIGURES_ROOT="$1" bash "$DF" check 2>&1); RC=$?; }

echo "== committed state =="
[ -f "$FIG/MODEL.md" ] && [ -f "$FIG/MANIFEST.tsv" ]
chk "docs/figures holds MODEL.md and MANIFEST.tsv" "$?"
OUT=$(bash "$DF" check 2>&1); RC=$?
chk "check passes on the committed repo" "$RC"
[ "$(cut -f1 "$FIG/MANIFEST.tsv" | tr '\n' ' ')" = "adopt board-row debug execute gauntlet lanes loop push-gate review several-pieces v-model wrap " ]
chk "the manifest holds exactly the twelve agreed ids, sorted" "$?"
n=0; for id in $(cut -f1 "$FIG/MANIFEST.tsv"); do [ -s "$FIG/$id.png" ] && n=$((n+1)); done
chk "every manifest id has a non-empty PNG" "$([ "$n" -eq 12 ]; echo $?)"

echo "== a clean copy passes =="
R=$(fresh clean); run "$R"
chk "check passes on a temp copy with valid README and guide references" "$RC"
printf '\nProse outside a sheet changes freely.\n' >> "$R/docs/figures/MODEL.md"; run "$R"
chk "prose outside any uml block does not need a re-render" "$RC"

echo "== an edited sheet without a re-render =="
R=$(fresh edited)
sed -i.bak 's/^title: The loop$/title: The loop, edited/' "$R/docs/figures/MODEL.md"
run "$R"
chk "check exits 1 after a block edit" "$([ "$RC" -eq 1 ]; echo $?)"
chk "the problem line names the sheet" "$(printf '%s\n' "$OUT" | grep -qE '^loop: sheet changed since the last render'; echo $?)"
chk "the other sheets are not blamed" "$([ "$(printf '%s\n' "$OUT" | wc -l | tr -d ' ')" -eq 1 ]; echo $?)"

echo "== a sheet missing from the manifest, and a manifest entry with no sheet =="
R=$(fresh newsheet)
printf '\n```uml\nid: extra\ntype: state\ntitle: Extra\nlevel: L1\nstates:\n  - {name: a}\n  - {name: b}\ntransitions:\n  - {from: a, to: b, event: go}\n```\n' >> "$R/docs/figures/MODEL.md"
run "$R"
chk "a new sheet with no render fails" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^extra: in the model, not in MANIFEST.tsv'; echo $?)"
R=$(fresh ghost)
printf 'ghost\t0000\n' >> "$R/docs/figures/MANIFEST.tsv"
run "$R"
chk "a manifest id with no sheet fails" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^ghost: in MANIFEST.tsv, not in the model'; echo $?)"
chk "a manifest id with no PNG fails too" "$(printf '%s\n' "$OUT" | grep -qE '^ghost: .*ghost.png is missing'; echo $?)"

echo "== a missing PNG =="
R=$(fresh nopng)
mv "$R/docs/figures/gauntlet.png" "$TMPD/gauntlet.png.gone"
run "$R"
chk "check exits 1 when a PNG is missing" "$([ "$RC" -eq 1 ]; echo $?)"
chk "the problem line names the figure" "$(printf '%s\n' "$OUT" | grep -qE '^gauntlet: .*gauntlet.png is missing'; echo $?)"
R=$(fresh straypng)
cp "$R/docs/figures/loop.png" "$R/docs/figures/stray.png"
run "$R"
chk "a PNG the manifest does not list fails" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^stray: .*not in MANIFEST.tsv'; echo $?)"

echo "== doc references =="
R=$(fresh badreadme)
printf '\n![x](docs/figures/no-such-figure.png)\n' >> "$R/README.md"
run "$R"
chk "an unknown id in README.md fails" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^README.md:[0-9]+: figures/no-such-figure.png names no manifest id'; echo $?)"
R=$(fresh badguide)
printf '\n![x](../figures/nope.png)\n' >> "$R/docs/guides/g.md"
run "$R"
chk "an unknown id in docs/guides fails and the line names the file" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^docs/guides/g.md:[0-9]+: figures/nope.png names no manifest id'; echo $?)"
R=$(fresh datedrecord)
mkdir -p "$R/docs/verification"
printf '\nThe negative test used `figures/nope.png`.\n' > "$R/docs/verification/proof.md"
run "$R"
chk "a dated record quoting an unknown id is not scanned" "$RC"
R=$(fresh placeholder)
printf '\nEmbed as `../figures/<id>.png` in a guide.\n' >> "$R/docs/guides/g.md"
run "$R"
chk "the <id> placeholder in prose is not a reference" "$RC"

echo "== short digests =="
R=$(fresh short)
awk -F'\t' -v OFS='\t' '{ print $1, substr($2, 1, 16) }' "$R/docs/figures/MANIFEST.tsv" >"$R/m" && mv -f "$R/m" "$R/docs/figures/MANIFEST.tsv"
run "$R"
chk "a manifest of 16-hex digests passes (render writes these)" "$RC"
awk -F'\t' -v OFS='\t' '$1 == "loop" { $2 = substr($2, 1, 15) "x" } 1' "$R/docs/figures/MANIFEST.tsv" >"$R/m" && mv -f "$R/m" "$R/docs/figures/MANIFEST.tsv"
run "$R"
chk "a wrong 16-hex digest fails and names the sheet" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^loop: sheet changed since the last render'; echo $?)"
R=$(fresh odd)
awk -F'\t' -v OFS='\t' '$1 == "loop" { $2 = substr($2, 1, 20) } 1' "$R/docs/figures/MANIFEST.tsv" >"$R/m" && mv -f "$R/m" "$R/docs/figures/MANIFEST.tsv"
run "$R"
chk "a digest that is neither 16 nor 64 hex fails" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^loop: sheet changed'; echo $?)"

echo "== rendered SVG figures =="
svgfig() { printf '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10" width="10" height="10"%s/>\n' "$2" > "$1"; }
R=$(fresh svgok)
mv "$R/docs/figures/loop.png" "$TMPD/loop.png.gone"
svgfig "$R/docs/figures/loop.svg" ' data-doc-figures="loop"'
run "$R"
chk "a rendered <id>.svg stands in for <id>.png" "$RC"
svgfig "$R/docs/figures/chart.svg" ''
run "$R"
chk "a hand-drawn SVG beside the figures is left alone" "$RC"
svgfig "$R/docs/figures/gone.svg" ' data-doc-figures="gone"'
run "$R"
chk "a rendered SVG the manifest does not list fails" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^gone: .*gone.svg is not in MANIFEST.tsv'; echo $?)"
R=$(fresh svghand)
mv "$R/docs/figures/loop.png" "$TMPD/loop2.png.gone"
svgfig "$R/docs/figures/loop.svg" ''
run "$R"
chk "a hand-drawn <id>.svg does not count as the rendered figure" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^loop: .*loop.png is missing'; echo $?)"
R=$(fresh svgboth)
svgfig "$R/docs/figures/loop.svg" ' data-doc-figures="loop"'
run "$R"
chk "both <id>.png and a rendered <id>.svg fail as a stale pair" "$([ "$RC" -eq 1 ] && printf '%s\n' "$OUT" | grep -qE '^loop: both loop.png and loop.svg are rendered'; echo $?)"

echo "== render flags (no browser) =="
R=$(fresh flags)
OUT=$(DOC_FIGURES_ROOT="$R" bash "$DF" render --format gif 2>&1); RC=$?
chk "render refuses an unknown --format" "$([ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'png or svg'; echo $?)"
OUT=$(DOC_FIGURES_ROOT="$R" bash "$DF" render --fz 9 2>&1); RC=$?
chk "render refuses an fz outside 0.5 to 3" "$([ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'fz must be'; echo $?)"
printf -- '---\nfz: big\n---\n' | cat - "$R/docs/figures/MODEL.md" > "$R/m" && mv -f "$R/m" "$R/docs/figures/MODEL.md"
OUT=$(DOC_FIGURES_ROOT="$R" bash "$DF" render 2>&1); RC=$?
chk "render refuses a non-numeric fz in the front matter" "$([ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'fz must be.*big'; echo $?)"
OUT=$(DOC_FIGURES_ROOT="$R" DOC_FIGURES_FORMAT=jpg bash "$DF" render 2>&1); RC=$?
chk "DOC_FIGURES_FORMAT is validated like --format" "$([ "$RC" -ne 0 ] && printf '%s\n' "$OUT" | grep -q 'jpg'; echo $?)"

echo "== usage =="
bash "$DF" frobnicate >/dev/null 2>&1
chk "an unknown verb is refused" "$([ $? -ne 0 ]; echo $?)"
DOC_FIGURES_ROOT="$TMPD/none" bash "$DF" check >/dev/null 2>&1
chk "check on a root with no model is refused" "$([ $? -ne 0 ]; echo $?)"

echo "== render (browser needed) =="
chrome=${CHROME:-}
if [ -z "$chrome" ]; then
  for c in "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" "/Applications/Microsoft Edge.app/Contents/MacOS/Microsoft Edge"; do
    [ -x "$c" ] && { chrome=$c; break; }
  done
fi
if ! command -v node >/dev/null 2>&1; then
  echo "  SKIP node not installed"
elif [ -z "$chrome" ] || [ ! -x "$chrome" ]; then
  echo "  SKIP no Chrome or Edge found (set CHROME)"
elif ! curl -fsS -m 8 -o /dev/null https://cdnjs.cloudflare.com/ajax/libs/js-yaml/4.1.0/js-yaml.min.js 2>/dev/null; then
  echo "  SKIP no network (the page loads js-yaml from cdnjs)"
else
  RM="$TMPD/render"; mkdir -p "$RM/docs/figures"
  cat > "$RM/docs/figures/MODEL.md" <<'EOF'
# Render test

```uml
id: tiny-flow
type: state
title: Tiny flow
level: L1
states:
  - {name: start, initial: true, at: [0, 0]}
  - {name: finish, final: true, at: [1, 0]}
transitions:
  - {from: start, to: finish, event: go, tone: blue}
```
EOF
  CHROME="$chrome" DOC_FIGURES_ROOT="$RM" bash "$DF" render >"$TMPD/render.log" 2>&1
  chk "render exits 0 on a one-sheet model" "$?"
  chk "render writes <id>.png, not d-<id>.png" "$([ -s "$RM/docs/figures/tiny-flow.png" ] && [ ! -e "$RM/docs/figures/d-tiny-flow.png" ]; echo $?)"
  chk "render writes MANIFEST.tsv with the id and a 16-hex digest" "$(grep -qE '^tiny-flow	[0-9a-f]{16}$' "$RM/docs/figures/MANIFEST.tsv"; echo $?)"
  run "$RM"
  chk "check passes straight after render" "$RC"

  # SVG mode: the same sheet as a standalone, theme-aware SVG with its fonts embedded.
  mv "$RM/docs/figures/tiny-flow.png" "$TMPD/tiny-flow.png.gone"
  CHROME="$chrome" DOC_FIGURES_ROOT="$RM" bash "$DF" render --format svg >"$TMPD/svg.log" 2>&1
  chk "render --format svg exits 0" "$?"
  SV="$RM/docs/figures/tiny-flow.svg"
  chk "render writes <id>.svg and no PNG" "$([ -s "$SV" ] && [ ! -e "$RM/docs/figures/tiny-flow.png" ]; echo $?)"
  vbw=$(grep -o 'viewBox="0 0 [0-9]*' "$SV" | head -1 | awk '{ print $3 }')
  chk "width equals the viewBox width at fz 1" "$(grep -q " width=\"$vbw\"" "$SV"; echo $?)"
  chk "the SVG carries the light tokens and a prefers-color-scheme dark block" "$(grep -q -- '--sheet: #ffffff' "$SV" && grep -q '@media (prefers-color-scheme: dark)' "$SV" && grep -q -- '--sheet: #141a21' "$SV"; echo $?)"
  chk "the drawing classes it uses come along (.state, .t-name)" "$(grep -q '^\.state {' "$SV" && grep -q '^\.t-name {' "$SV"; echo $?)"
  chk "fonts are embedded as data URIs, nothing is fetched" "$(grep -q 'url(data:font/' "$SV" && ! grep -qE 'url\((https?:|//)' "$SV"; echo $?)"
  chk "the SVG stays under 150 KB ($(wc -c <"$SV" | tr -d ' ') bytes)" "$([ "$(wc -c <"$SV")" -lt 153600 ]; echo $?)"
  chk "the SVG carries the rendered-figure marker" "$(grep -q 'data-doc-figures="tiny-flow"' "$SV"; echo $?)"
  if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$SV" 2>/dev/null; chk "the SVG is well-formed XML" "$?"; fi
  run "$RM"
  chk "check passes straight after an SVG render" "$RC"
  printf -- '---\nfz: 1.5\n---\n' | cat - "$RM/docs/figures/MODEL.md" > "$RM/m" && mv -f "$RM/m" "$RM/docs/figures/MODEL.md"
  CHROME="$chrome" DOC_FIGURES_ROOT="$RM" bash "$DF" render --format svg >"$TMPD/svg15.log" 2>&1
  chk "front matter fz: 1.5 scales the SVG to 1.5 times its viewBox" "$(grep -q " width=\"$(( (vbw * 3 + 1) / 2 ))\"" "$SV"; echo $?)"
  CHROME="$chrome" DOC_FIGURES_ROOT="$RM" bash "$DF" render --format svg --fz 1 >"$TMPD/svg1.log" 2>&1
  chk "the --fz flag wins over the front matter" "$(grep -q " width=\"$vbw\"" "$SV"; echo $?)"
  # PNG at fz 1.5: the canvas holds the drawing at 1.5 times its viewBox plus a 1 px border each side, at SHOT_SCALE 2.
  mv "$SV" "$TMPD/tiny-flow.svg.gone"
  CHROME="$chrome" DOC_FIGURES_ROOT="$RM" bash "$DF" render >"$TMPD/png15.log" 2>&1
  w15=$(od -An -tu1 -j16 -N4 "$RM/docs/figures/tiny-flow.png" | awk 'NF { print $1*16777216 + $2*65536 + $3*256 + $4 }')
  chk "front matter fz scales the PNG too ($w15 px for a $vbw-unit drawing)" "$([ "$w15" -eq $(( ((vbw * 3 + 1) / 2 + 2) * 2 )) ]; echo $?)"
fi

echo
echo "doc-figures: $PASS passed, $FAIL failed ($TOTAL checks)"
[ "$FAIL" -eq 0 ]
