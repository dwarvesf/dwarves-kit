#!/usr/bin/env bash
# TASK-010: idempotent install/uninstall of the settings.json hook entries. Operates on a temp
# settings.json (CC_SI_SETTINGS); never touches the real one. Run: bash tests/test-install.sh
set -uo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL="$DIR/deploy/install.sh"; UNINSTALL="$DIR/deploy/uninstall.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
pass=0; fail=0
ok(){ echo "  ok: $*"; pass=$((pass+1)); }
no(){ echo "  FAIL: $*" >&2; fail=$((fail+1)); }
export CC_SI_SETTINGS="$TMP/settings.json" CC_SI_STATE_DIR="$TMP/state"
ncsi(){ jq '[.hooks[]?[]?.hooks[]?.command | select(test("cc-self-improve"))] | length' "$CC_SI_SETTINGS" 2>/dev/null; }

# Pre-existing unrelated hook (must survive install + uninstall).
jq -n '{hooks:{PreCompact:[{matcher:"",hooks:[{type:"command",command:"/x/unrelated.sh",async:true}]}]}}' > "$CC_SI_SETTINGS"

echo "[1] install adds skill-review (PreCompact+SessionEnd) + surface (SessionStart), all async"
bash "$INSTALL" >/dev/null 2>&1
pc="$(jq -r '[.hooks.PreCompact[]?.hooks[]?|select(.command|test("skill-review.sh"))]|length' "$CC_SI_SETTINGS")"
se="$(jq -r '[.hooks.SessionEnd[]?.hooks[]?|select(.command|test("skill-review.sh"))]|length' "$CC_SI_SETTINGS")"
ss="$(jq -r '[.hooks.SessionStart[]?.hooks[]?|select(.command|test("sessionstart-surface.sh"))]|length' "$CC_SI_SETTINGS")"
allasync="$(jq -r '[.hooks[]?[]?.hooks[]?|select(.command|test("cc-self-improve"))|.async]|all(.==true)' "$CC_SI_SETTINGS")"
if [[ "$pc" -eq 1 && "$se" -eq 1 && "$ss" -eq 1 && "$allasync" == "true" ]]; then ok "3 entries added, all async"; else no "install entries wrong: pc=$pc se=$se ss=$ss async=$allasync"; fi

echo "[2] install is idempotent (twice -> no duplicate entries)"
before="$(ncsi)"; bash "$INSTALL" >/dev/null 2>&1; after="$(ncsi)"
if [[ "$before" -eq 3 && "$after" -eq 3 ]]; then ok "still 3 entries after second install"; else no "dup on second install: $before -> $after"; fi

echo "[3] install backed up settings.json first"
if [[ -n "$(find "$TMP" -name 'settings.json.bak-*' 2>/dev/null)" ]]; then ok "backup created"; else no "no backup"; fi

echo "[4] the pre-existing unrelated hook survived install"
if jq -e '[.hooks.PreCompact[]?.hooks[]?|select(.command=="/x/unrelated.sh")]|length==1' "$CC_SI_SETTINGS" >/dev/null; then ok "unrelated hook intact"; else no "unrelated hook lost"; fi

echo "[5] uninstall removes ONLY cc-self-improve entries; unrelated survives"
bash "$UNINSTALL" >/dev/null 2>&1
left="$(ncsi)"; unrel="$(jq -r '[.hooks.PreCompact[]?.hooks[]?|select(.command=="/x/unrelated.sh")]|length' "$CC_SI_SETTINGS")"
if [[ "$left" -eq 0 && "$unrel" -eq 1 ]]; then ok "cc-self-improve removed, unrelated kept"; else no "uninstall wrong: left=$left unrel=$unrel"; fi

echo "[6] install on a missing settings.json creates valid JSON"
rm -f "$CC_SI_SETTINGS"
bash "$INSTALL" >/dev/null 2>&1
if jq -e . "$CC_SI_SETTINGS" >/dev/null 2>&1 && [[ "$(ncsi)" -eq 3 ]]; then ok "created valid settings with 3 entries"; else no "missing-file install failed"; fi

echo
if [[ $fail -gt 0 ]]; then echo "test-install: $pass passed, $fail FAILED" >&2; exit 1; fi
echo "test-install: all $pass passed"
