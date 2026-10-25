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
  chk "render writes MANIFEST.tsv with the id and a sha256" "$(grep -qE '^tiny-flow	[0-9a-f]{64}$' "$RM/docs/figures/MANIFEST.tsv"; echo $?)"
  run "$RM"
  chk "check passes straight after render" "$RC"
fi

echo
echo "doc-figures: $PASS passed, $FAIL failed ($TOTAL checks)"
[ "$FAIL" -eq 0 ]
