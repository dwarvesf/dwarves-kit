#!/usr/bin/env bash
# test-system-design.sh -- lib/system-design/build renders a model, refuses a hostile one, and the
# engine's own smoke test (node test.mjs) passes when node and network are available.
#
# Run: bash tests/test-system-design.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SD="$KIT_DIR/lib/system-design"
EX="$SD/examples/marketplace"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
chk() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-sysdesign-test.XXXXXX")" || exit 1
trap 'rm -rf "$TMPD"' EXIT

echo "== system-design build =="
title=$(sed -n 's/^# //p' "$EX/SYSTEM-DESIGN.md" | head -n 1)
OUT="$TMPD/uml.html"
bash "$SD/build" --model "$EX/SYSTEM-DESIGN.md" --base-file "$EX/SYSTEM-DESIGN.base.md" --out "$OUT" >"$TMPD/build.log" 2>&1
chk "build exits 0 on the marketplace fixture with a base file" "$?"
chk "model title is non-empty" "$([ -n "$title" ]; echo $?)"
chk "output contains the model title" "$(grep -qF -- "$title" "$OUT" 2>/dev/null; echo $?)"
chk "output embeds the base model" "$(grep -qF 'id="uml-base"' "$OUT" 2>/dev/null; echo $?)"
chk "no build placeholder survives" "$(grep -q '__UML_\|__DELTA_JS__\|__LAYOUT_JS__\|__MODEL__\|__BASE_REF__\|__TITLE__' "$OUT" 2>/dev/null && echo 1 || echo 0)"

echo "== refusals =="
BAD="$TMPD/bad.md"
printf '# Bad model\n\n</script><script>alert(1)</script>\n' > "$BAD"
bash "$SD/build" --model "$BAD" --out "$TMPD/bad.html" >"$TMPD/bad.log" 2>&1
rc=$?
chk "a model containing </script is refused (non-zero exit)" "$([ "$rc" -ne 0 ]; echo $?)"
chk "the refusal names </script" "$(grep -qF '</script' "$TMPD/bad.log"; echo $?)"
chk "no output file is written for a refused model" "$([ ! -e "$TMPD/bad.html" ]; echo $?)"
bash "$SD/build" --model "$EX/SYSTEM-DESIGN.md" >/dev/null 2>&1
chk "build without --out is refused" "$([ $? -ne 0 ]; echo $?)"

echo "== engine smoke test (node test.mjs) =="
if ! command -v node >/dev/null 2>&1; then
  echo "  SKIP node not installed"
elif ! curl -fsS -m 8 -o /dev/null https://cdnjs.cloudflare.com/ajax/libs/js-yaml/4.1.0/js-yaml.min.js 2>/dev/null; then
  echo "  SKIP no network (test.mjs fetches js-yaml from cdnjs)"
else
  node "$SD/test.mjs" >"$TMPD/node.log" 2>&1
  chk "node lib/system-design/test.mjs exits 0" "$?"
fi

echo
echo "system-design: $PASS passed, $FAIL failed ($TOTAL checks)"
[ "$FAIL" -eq 0 ]
