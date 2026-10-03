#!/usr/bin/env bash
# test-proof-asset.sh -- bin/proof-asset put/flush (the visual-proof asset pipeline:
# convert + cap, sha256, local cache, committed manifest, upload-or-queue, flush).
#   - put online through the uploader stub   -> status uploaded, a ![name](url) line,
#                                               key shaped <owner>/<repo>/<slug>/<rand>/<name>.<ext>
#   - put with the uploader failing          -> status pending, exit 0, one stderr line "queued"
#   - flush after recovery / again / still down -> uploaded + exit 0 / silent exit 0 / exit 1
#   - over the byte cap (still and GIF)      -> exit 2 naming the measured size, no manifest
#   - re-put of the same name                -> same key, still one manifest entry
#   - a converter that emits PNG (no WebP)   -> the .png path
#   - credential hygiene                     -> the token reaches the uploader's env, never
#                                               stdout, stderr, or the manifest
#   - assets = "local"                       -> cache + manifest only, no upload attempted
# Hermetic: temp repos only; the uploader, the converter, wrangler and secret-cache-read
# are stubs; the config layers are pinned to temp files; no network.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$KIT/bin/proof-asset"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fails=0
pass(){ echo "PASS $*"; }
fail(){ echo "FAIL $*"; fails=$((fails+1)); }

# Config layers pinned to temp homes: never the real operator or kit kit.toml.
export KIT_CONFIG_ROOT="$TMP/kitroot" KIT_CONFIG_OPERATOR="$TMP/op"
mkdir -p "$KIT_CONFIG_ROOT" "$KIT_CONFIG_OPERATOR"
cat > "$KIT_CONFIG_OPERATOR/kit.toml" <<'EOF'
[proof]
account_acme = "acct-test-123"
base_url_acme = "https://proof.test"
EOF

STUB="$TMP/stub"; mkdir -p "$STUB/bin"
export UP_LOG="$TMP/up.log" UP_FAIL="$TMP/up.fail" WRANGLER_ENV="$TMP/wrangler.env"
: > "$UP_LOG"

# Seam stubs. The uploader records its argv, fails while $UP_FAIL exists.
cat > "$STUB/uploader.sh" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$UP_LOG"
[ -f "$UP_FAIL" ] && exit 1
exit 0
EOF
# Converters: emit webp / png magic + payload; conv-big emits a >300KB webp.
cat > "$STUB/conv-webp.sh" <<'EOF'
#!/usr/bin/env bash
{ printf 'RIFF\x00\x00\x00\x00WEBPVP8L'; head -c 256 /dev/zero; } > "$2"
EOF
cat > "$STUB/conv-png.sh" <<'EOF'
#!/usr/bin/env bash
{ printf '\x89PNG\r\n\x1a\n'; head -c 256 /dev/zero; } > "$2"
EOF
cat > "$STUB/conv-big.sh" <<'EOF'
#!/usr/bin/env bash
{ printf 'RIFF\x00\x00\x00\x00WEBPVP8L'; head -c 400000 /dev/zero; } > "$2"
EOF
# Credential-path stubs: the token must reach the uploader's environment and nothing else.
cat > "$STUB/bin/secret-cache-read" <<'EOF'
#!/usr/bin/env bash
echo "FAKE_TOKEN_deadbeef0123456789"
EOF
cat > "$STUB/bin/wrangler" <<'EOF'
#!/usr/bin/env bash
env | grep '^CLOUDFLARE_' > "$WRANGLER_ENV"
printf '%s\n' "$*" >> "$UP_LOG"
[ -f "$UP_FAIL" ] && exit 1
exit 0
EOF
chmod +x "$STUB"/*.sh "$STUB/bin/"*

mkrepo() {  # mkrepo <dir> -- a git repo posing as github.com/acme/widgets
  local d="$1"
  rm -rf "$d"; mkdir -p "$d"
  git -C "$d" init -q -b main 2>/dev/null
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  git -C "$d" remote add origin git@github.com:acme/widgets.git
  echo base > "$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm base
}
mkimg() { { printf '\x89PNG\r\n\x1a\n'; head -c 2000 /dev/urandom; } > "$1"; }

R=""; OUT=""; ERR=""; RC=0
run() { OUT="$(cd "$R" && "$@" 2>"$TMP/e")"; RC=$?; ERR="$(cat "$TMP/e")"; }
manifest() { echo "$R/docs/verification/$1/assets.json"; }

echo "== 13: put online via the uploader stub =="
R="$TMP/r13"; mkrepo "$R"; mkimg "$R/img.png"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t13 img.png --name shot
[ $RC -eq 0 ] && pass "put exits 0" || fail "put rc=$RC ($ERR)"
printf '%s' "$OUT" | grep -qE '^!\[shot\]\(https://proof\.test/acme/widgets/t13/[0-9a-f]{32}/shot\.webp\)$' \
  && pass "prints ![shot](<base>/<owner>/<repo>/<slug>/<rand>/shot.webp)" || fail "bad paste line: $OUT"
M="$(manifest t13)"
[ -f "$M" ] && pass "manifest written" || fail "no manifest"
[ -f "$R/.kit/proof-assets/t13/shot.webp" ] && pass "image cached under .kit/proof-assets/" || fail "no cache file"
[ "$(jq -r '.assets[0].status' "$M" 2>/dev/null)" = uploaded ] && pass "entry status uploaded" || fail "status=$(jq -r '.assets[0].status' "$M" 2>/dev/null)"
SHA="$(shasum -a 256 "$R/.kit/proof-assets/t13/shot.webp" 2>/dev/null | awk '{print $1}')"
{ [ -n "$SHA" ] && [ "$(jq -r '.assets[0].sha256' "$M" 2>/dev/null)" = "$SHA" ]; } \
  && pass "manifest sha256 matches the cached bytes" || fail "sha mismatch"
RAND_OUT="$(printf '%s' "$OUT" | sed -E 's#.*t13/([0-9a-f]{32})/.*#\1#')"
{ [ -n "$RAND_OUT" ] && [ "$(jq -r '.rand' "$M" 2>/dev/null)" = "$RAND_OUT" ]; } \
  && pass "manifest rand is the url rand, stored once" || fail "rand mismatch"
grep -qE "acme/widgets/t13/[0-9a-f]{32}/shot\.webp acct-test-123$" "$UP_LOG" \
  && pass "uploader called as <file> <key> <account-id>" || fail "uploader log: $(tail -1 "$UP_LOG" 2>/dev/null)"

echo "== 14: put with the uploader failing =="
R="$TMP/r14"; mkrepo "$R"; mkimg "$R/img.png"; : > "$UP_FAIL"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t14 img.png --name shot
[ $RC -eq 0 ] && pass "failed upload still exits 0" || fail "rc=$RC"
[ "$(jq -r '.assets[0].status' "$(manifest t14)" 2>/dev/null)" = pending ] && pass "entry stays pending" || fail "not pending"
printf '%s' "$ERR" | grep -q queued && pass "one stderr line says queued" || fail "stderr: $ERR"
printf '%s' "$OUT" | grep -qE '^!\[shot\]\(https://proof\.test/' && pass "the paste line still prints the future url" || fail "no paste line"

echo "== 15: flush after the uploader recovers =="
rm -f "$UP_FAIL"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush
[ $RC -eq 0 ] && pass "flush exits 0" || fail "flush rc=$RC ($ERR)"
[ "$(jq -r '.assets[0].status' "$(manifest t14)" 2>/dev/null)" = uploaded ] && pass "pending -> uploaded" || fail "still pending"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush
{ [ $RC -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; } \
  && pass "nothing pending: exit 0, no output" || fail "second flush: rc=$RC out=[$OUT] err=[$ERR]"

echo "== 16: flush with the uploader still failing =="
R="$TMP/r16"; mkrepo "$R"; mkimg "$R/img.png"; : > "$UP_FAIL"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t16 img.png --name shot
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush
[ $RC -eq 1 ] && pass "flush exits 1 with an entry still pending" || fail "flush rc=$RC"
rm -f "$UP_FAIL"

echo "== 17: over the cap after conversion (still and GIF) =="
R="$TMP/r17"; mkrepo "$R"; mkimg "$R/img.png"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-big.sh" \
  bash "$BIN" put t17 img.png --name shot
SZ="$(printf '%s' "$OUT$ERR" | grep -oE '[0-9]+ bytes' | grep -oE '[0-9]+' | head -1)"
{ [ $RC -eq 2 ] && [ -n "$SZ" ] && [ "$SZ" -gt 307200 ]; } \
  && pass "still over 300KB: exit 2 with the measured size" || fail "rc=$RC out=[$OUT] err=[$ERR]"
{ printf 'GIF89a'; head -c 2300000 /dev/zero; } > "$R/big.gif"
GSIZE="$(wc -c < "$R/big.gif" | tr -d ' ')"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t17 big.gif --name clip
{ [ $RC -eq 2 ] && printf '%s' "$OUT$ERR" | grep -q "$GSIZE"; } \
  && pass "GIF over 2MB: exit 2 with the measured size" || fail "rc=$RC out=[$OUT] err=[$ERR]"
[ ! -f "$(manifest t17)" ] && pass "an over-cap put writes no manifest" || fail "manifest written on over-cap"

echo "== 18: re-put of the same name =="
R="$TMP/r18"; mkrepo "$R"; mkimg "$R/img.png"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t18 img.png --name shot
L1="$OUT"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t18 img.png --name shot
{ [ -n "$OUT" ] && [ "$OUT" = "$L1" ] && printf '%s' "$OUT" | grep -q 't18/'; } \
  && pass "same key on re-put (identical url line)" || fail "url drifted: $L1 -> $OUT"
[ "$(jq '.assets | length' "$(manifest t18)" 2>/dev/null)" = 1 ] && pass "still one manifest entry" || fail "entries=$(jq '.assets | length' "$(manifest t18)" 2>/dev/null)"

echo "== 19: no WebP encoder answers (convert seam emits PNG) =="
R="$TMP/r19"; mkrepo "$R"; { printf '\xff\xd8\xff\xe0'; head -c 1000 /dev/zero; } > "$R/img.jpg"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-png.sh" \
  bash "$BIN" put t19 img.jpg --name shot
{ [ $RC -eq 0 ] && [ "$(jq -r '.assets[0].file' "$(manifest t19)" 2>/dev/null)" = shot.png ] \
  && printf '%s' "$OUT" | grep -q 'shot\.png)'; } \
  && pass "PNG path taken: entry file and url carry .png" || fail "rc=$RC file=$(jq -r '.assets[0].file' "$(manifest t19)" 2>/dev/null) out=$OUT"

echo "== 20: no credential-shaped string in put/flush output =="
R="$TMP/r20"; mkrepo "$R"; mkimg "$R/img.png"
printf 'asset_token_ref = "op://test/proof-token"\n' >> "$KIT_CONFIG_OPERATOR/kit.toml"
STUPATH="$STUB/bin:/usr/bin:/bin:/opt/homebrew/bin"
run env PATH="$STUPATH" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t20 img.png --name shot
{ [ $RC -eq 0 ] && ! printf '%s' "$OUT$ERR" | grep -q 'FAKE_TOKEN_deadbeef' \
  && ! printf '%s' "$OUT$ERR" | grep -q 'op://'; } \
  && pass "put output holds neither the token nor its ref" || fail "leak: rc=$RC out=[$OUT] err=[$ERR]"
grep -q '^CLOUDFLARE_API_TOKEN=FAKE_TOKEN_deadbeef' "$WRANGLER_ENV" \
  && pass "the token reached the uploader through the env" || fail "wrangler env: $(cat "$WRANGLER_ENV" 2>/dev/null)"
grep -q '^CLOUDFLARE_ACCOUNT_ID=acct-test-123' "$WRANGLER_ENV" \
  && pass "the account id reached the uploader env" || fail "no account id in uploader env"
grep -qE "r2 object put kit-proof-assets/acme/widgets/t20/[0-9a-f]{32}/shot\.webp --file .* --remote" "$UP_LOG" \
  && pass "default uploader ran wrangler r2 object put <bucket>/<key>" || fail "wrangler argv: $(tail -1 "$UP_LOG" 2>/dev/null)"
! grep -q 'FAKE_TOKEN' "$(manifest t20)" && pass "the manifest holds no token" || fail "manifest leaked the token"
R="$TMP/r20b"; mkrepo "$R"; mkimg "$R/img.png"; : > "$UP_FAIL"
run env PATH="$STUPATH" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t20b img.png --name shot
rm -f "$UP_FAIL"
run env PATH="$STUPATH" bash "$BIN" flush
{ [ $RC -eq 0 ] && ! printf '%s' "$OUT$ERR" | grep -q 'FAKE_TOKEN_deadbeef'; } \
  && pass "flush output holds no token" || fail "flush leak/rc=$RC: [$OUT] [$ERR]"

echo "== assets = local: cache + manifest, never an upload =="
R="$TMP/rlocal"; mkrepo "$R"; mkimg "$R/img.png"
printf '[proof]\nassets = "local"\n' > "$R/.kit.toml"
BEFORE="$(wc -l < "$UP_LOG" | tr -d ' ')"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put tloc img.png --name shot
{ [ $RC -eq 0 ] && [ "$(jq -r '.assets[0].status' "$(manifest tloc)" 2>/dev/null)" = local ]; } \
  && pass "entry status local" || fail "rc=$RC status=$(jq -r '.assets[0].status' "$(manifest tloc)" 2>/dev/null)"
[ "$(wc -l < "$UP_LOG" | tr -d ' ')" = "$BEFORE" ] && pass "no upload attempted in local mode" || fail "uploader ran in local mode"
printf '%s' "$OUT" | grep -q 'shot' && pass "prints a paste line" || fail "no paste line"

echo "== usage and outside-a-repo guards =="
OUT="$(bash "$BIN" 2>&1)"; RC=$?
{ [ $RC -eq 64 ] && printf '%s' "$OUT" | grep -q 'usage: proof-asset'; } && pass "no args -> usage, exit 64" || fail "rc=$RC out=[$OUT]"
R="$TMP/notrepo"; rm -rf "$R"; mkdir -p "$R"
run bash "$BIN" put x f.png
{ [ $RC -ne 0 ] && printf '%s' "$ERR" | grep -qi 'repo'; } && pass "outside a git repo -> nonzero, says why" || fail "rc=$RC err=[$ERR]"

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
