#!/usr/bin/env bash
# test-proof-asset.sh -- bin/proof-asset put/flush (the visual-proof asset pipeline:
# convert + cap, sha256, local cache, committed manifest, upload-or-queue, flush).
# Model: the committed manifest only ever holds the FINAL entry (status r2|local is
# the destination, never progress); upload progress lives only in the gitignored
# .kit/proof-assets/<slug>/.pending queue, one file name per line.
#   - put online through the uploader stub   -> status r2, a ![name](url) line, key
#                                               <owner>/<repo>/<slug>/<rand>/<name>-<sha8>.<ext>
#   - put with the uploader failing          -> status r2 + a .pending line, exit 0,
#                                               one stderr line "queued"
#   - flush after recovery / again / still down -> the .pending line drains, the
#                                               ![name](url) line prints, the manifest
#                                               is NEVER rewritten / silent 0 / exit 1
#   - over the byte cap (still and GIF)      -> exit 2 naming the measured size, no manifest
#   - re-put of the same name                -> one manifest entry; new bytes -> new
#                                               sha8 in the file name, so the key moves
#   - a converter that emits PNG (no WebP)   -> the .png path
#   - a JPEG no encoder can convert          -> sips ->png when it exists, else exit 2
#   - assets = r2 with no proof.base_url_*   -> exit 1 naming the key, writes nothing
#   - credential hygiene                     -> the token reaches the uploader's env, never
#                                               stdout, stderr, or the manifest
#   - manifest / queue traversal             -> bad file/rand/slug/assets skipped + warned,
#                                               never uploaded
#   - assets = "local"                       -> cache + manifest only, no upload attempted
#   - the land round trip                    -> offline put, commit, flush, the tree is
#                                               clean enough for land's dirty check
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
mkdir -p "$KIT_CONFIG_ROOT" "$KIT_CONFIG_OPERATOR" "$TMP/op-nobase" "$TMP/op-slash"
cat > "$KIT_CONFIG_OPERATOR/kit.toml" <<'EOF'
[proof]
account_acme = "acct-test-123"
base_url_acme = "https://proof.test"
EOF
cat > "$TMP/op-nobase/kit.toml" <<'EOF'
[proof]
account_acme = "acct-test-123"
EOF
cat > "$TMP/op-slash/kit.toml" <<'EOF'
[proof]
account_acme = "acct-test-123"
base_url_acme = "https://proof.test/"
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
cat > "$STUB/conv-fail.sh" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
# conv-real: webp magic + the input bytes, so distinct inputs hash to distinct outputs.
cat > "$STUB/conv-real.sh" <<'EOF'
#!/usr/bin/env bash
{ printf 'RIFF\x00\x00\x00\x00WEBPVP8L'; cat "$1"; } > "$2"
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
# No-encoder stubs: shadow cwebp/pngquant/sips with failures when a case needs every
# converter to lose.
mkdir -p "$STUB/noenc" "$STUB/nocwebp"
for c in cwebp pngquant sips; do printf '#!/bin/sh\nexit 1\n' > "$STUB/noenc/$c"; done
for c in cwebp pngquant; do printf '#!/bin/sh\nexit 1\n' > "$STUB/nocwebp/$c"; done
chmod +x "$STUB/noenc/"* "$STUB/nocwebp/"*

mkrepo() {  # mkrepo <dir> -- a git repo posing as github.com/acme/widgets
  local d="$1"
  rm -rf "$d"; mkdir -p "$d"
  git -C "$d" init -q -b main 2>/dev/null
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  git -C "$d" remote add origin git@github.com:acme/widgets.git
  echo base > "$d/README.md"; git -C "$d" add -A; git -C "$d" commit -qm base
}
mkimg() { { printf '\x89PNG\r\n\x1a\n'; head -c 2000 /dev/urandom; } > "$1"; }
# A real decodable 1x1 PNG for the sips path (sips refuses magic-byte fakes).
mkrealpng() {
  printf '%s' 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==' \
    | openssl base64 -d -A > "$1"
}

R=""; OUT=""; ERR=""; RC=0
run() { OUT="$(cd "$R" && "$@" 2>"$TMP/e")"; RC=$?; ERR="$(cat "$TMP/e")"; }
manifest() { echo "$R/docs/verification/$1/assets.json"; }
queue()    { echo "$R/.kit/proof-assets/$1/.pending"; }
mfile()    { jq -r '.assets[0].file' "$(manifest "$1")" 2>/dev/null; }

echo "== 13: put online via the uploader stub =="
R="$TMP/r13"; mkrepo "$R"; mkimg "$R/img.png"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t13 img.png --name shot
[ $RC -eq 0 ] && pass "put exits 0" || fail "put rc=$RC ($ERR)"
printf '%s' "$OUT" | grep -qE '^!\[shot\]\(https://proof\.test/acme/widgets/t13/[0-9a-f]{32}/shot-[0-9a-f]{8}\.webp\)$' \
  && pass "prints ![shot](<base>/<owner>/<repo>/<slug>/<rand>/shot-<sha8>.webp)" || fail "bad paste line: $OUT"
M="$(manifest t13)"
[ -f "$M" ] && pass "manifest written" || fail "no manifest"
F13="$(mfile t13)"
[ -n "$F13" ] && [ -f "$R/.kit/proof-assets/t13/$F13" ] && pass "image cached under .kit/proof-assets/" || fail "no cache file"
[ "$(jq -r '.assets[0].status' "$M" 2>/dev/null)" = r2 ] && pass "entry status r2 (destination, not progress)" || fail "status=$(jq -r '.assets[0].status' "$M" 2>/dev/null)"
SHA="$(shasum -a 256 "$R/.kit/proof-assets/t13/$F13" 2>/dev/null | awk '{print $1}')"
{ [ -n "$SHA" ] && [ "$(jq -r '.assets[0].sha256' "$M" 2>/dev/null)" = "$SHA" ]; } \
  && pass "manifest sha256 matches the cached bytes" || fail "sha mismatch"
printf '%s' "$F13" | grep -q "shot-${SHA:0:8}\.webp" \
  && pass "the file name carries the first 8 sha hex (edge-cache bust)" || fail "file=$F13 sha=$SHA"
RAND_OUT="$(printf '%s' "$OUT" | sed -E 's#.*t13/([0-9a-f]{32})/.*#\1#')"
{ [ -n "$RAND_OUT" ] && [ "$(jq -r '.rand' "$M" 2>/dev/null)" = "$RAND_OUT" ]; } \
  && pass "manifest rand is the url rand, stored once" || fail "rand mismatch"
grep -qE "acme/widgets/t13/[0-9a-f]{32}/shot-[0-9a-f]{8}\.webp acct-test-123$" "$UP_LOG" \
  && pass "uploader called as <file> <key> <account-id>" || fail "uploader log: $(tail -1 "$UP_LOG" 2>/dev/null)"
[ "$(cat "$R/.kit/proof-assets/.gitignore" 2>/dev/null)" = '*' ] \
  && pass "put writes .kit/proof-assets/.gitignore holding '*'" || fail "no cache .gitignore"

echo "== 14: put with the uploader failing =="
R="$TMP/r14"; mkrepo "$R"; mkimg "$R/img.png"; : > "$UP_FAIL"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t14 img.png --name shot
[ $RC -eq 0 ] && pass "failed upload still exits 0" || fail "rc=$RC"
[ "$(jq -r '.assets[0].status' "$(manifest t14)" 2>/dev/null)" = r2 ] \
  && pass "manifest status stays r2 (destination)" || fail "status=$(jq -r '.assets[0].status' "$(manifest t14)" 2>/dev/null)"
[ "$(cat "$(queue t14)" 2>/dev/null)" = "$(mfile t14)" ] \
  && pass "the .pending queue holds the file name" || fail "queue: $(cat "$(queue t14)" 2>/dev/null)"
printf '%s' "$ERR" | grep -q queued && pass "one stderr line says queued" || fail "stderr: $ERR"
printf '%s' "$OUT" | grep -qE '^!\[shot\]\(https://proof\.test/' && pass "the paste line still prints the future url" || fail "no paste line"
PRE15="$(cat "$(manifest t14)")"

echo "== 15: flush after the uploader recovers =="
rm -f "$UP_FAIL"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush
[ $RC -eq 0 ] && pass "flush exits 0" || fail "flush rc=$RC ($ERR)"
[ ! -f "$(queue t14)" ] && pass "the .pending queue drains" || fail "queue still there"
[ "$(cat "$(manifest t14)")" = "$PRE15" ] \
  && pass "flush never rewrites the committed manifest" || fail "manifest changed on flush"
printf '%s' "$OUT" | grep -qE '^!\[shot\]\(https://proof\.test/acme/widgets/t14/[0-9a-f]{32}/shot-[0-9a-f]{8}\.webp\)$' \
  && pass "flush prints the ![name](url) line for what it uploaded" || fail "no paste line: $OUT"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush
{ [ $RC -eq 0 ] && [ -z "$OUT" ] && [ -z "$ERR" ]; } \
  && pass "nothing pending: exit 0, no output" || fail "second flush: rc=$RC out=[$OUT] err=[$ERR]"

echo "== 16: flush with the uploader still failing =="
R="$TMP/r16"; mkrepo "$R"; mkimg "$R/img.png"; : > "$UP_FAIL"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t16 img.png --name shot
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush
{ [ $RC -eq 1 ] && [ -s "$(queue t16)" ]; } \
  && pass "flush exits 1 with the line still pending" || fail "flush rc=$RC"
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
  && pass "same key on re-put of identical bytes" || fail "url drifted: $L1 -> $OUT"
mkimg "$R/img2.png"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-real.sh" \
  bash "$BIN" put t18 img2.png --name shot
{ [ -n "$OUT" ] && [ "$OUT" != "$L1" ]; } \
  && pass "new bytes move the key (sha8 changes, stale edge cache cannot bite)" || fail "url did not move: $OUT"
[ "$(jq '.assets | length' "$(manifest t18)" 2>/dev/null)" = 1 ] && pass "still one manifest entry" || fail "entries=$(jq '.assets | length' "$(manifest t18)" 2>/dev/null)"

echo "== 19: no WebP encoder answers (convert seam emits PNG) =="
R="$TMP/r19"; mkrepo "$R"; { printf '\xff\xd8\xff\xe0'; head -c 1000 /dev/zero; } > "$R/img.jpg"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-png.sh" \
  bash "$BIN" put t19 img.jpg --name shot
{ [ $RC -eq 0 ] && printf '%s' "$(mfile t19)" | grep -qE '^shot-[0-9a-f]{8}\.png$' \
  && printf '%s' "$OUT" | grep -q '\.png)'; } \
  && pass "PNG path taken: entry file and url carry .png" || fail "rc=$RC file=$(mfile t19) out=$OUT"

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
grep -qE "r2 object put kit-proof-assets/acme/widgets/t20/[0-9a-f]{32}/shot-[0-9a-f]{8}\.webp --file .* --remote" "$UP_LOG" \
  && pass "default uploader ran wrangler r2 object put <bucket>/<key>" || fail "wrangler argv: $(tail -1 "$UP_LOG" 2>/dev/null)"
! grep -q 'FAKE_TOKEN' "$(manifest t20)" && pass "the manifest holds no token" || fail "manifest leaked the token"
R="$TMP/r20b"; mkrepo "$R"; mkimg "$R/img.png"; : > "$UP_FAIL"
run env PATH="$STUPATH" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put t20b img.png --name shot
rm -f "$UP_FAIL"
run env PATH="$STUPATH" bash "$BIN" flush
{ [ $RC -eq 0 ] && ! printf '%s' "$OUT$ERR" | grep -q 'FAKE_TOKEN_deadbeef'; } \
  && pass "flush output holds no token" || fail "flush leak/rc=$RC: [$OUT] [$ERR]"

echo "== r2 with no base url: exit 1 naming the key, writing nothing =="
R="$TMP/rnobase"; mkrepo "$R"; mkimg "$R/img.png"
run env KIT_CONFIG_OPERATOR="$TMP/op-nobase" PROOF_ASSET_UPLOADER="$STUB/uploader.sh" \
  PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" bash "$BIN" put tnb img.png --name shot
{ [ $RC -eq 1 ] && printf '%s' "$ERR" | grep -q 'proof.base_url_acme'; } \
  && pass "missing base url exits 1 naming proof.base_url_<owner>" || fail "rc=$RC err=[$ERR]"
{ [ ! -f "$(manifest tnb)" ] && [ ! -d "$R/.kit" ]; } \
  && pass "writes nothing (no manifest, no cache)" || fail "left files behind"
R="$TMP/rnoorigin"; rm -rf "$R"; mkdir -p "$R"
git -C "$R" init -q -b main; git -C "$R" config user.email t@t; git -C "$R" config user.name t
echo x > "$R/a"; git -C "$R" add -A; git -C "$R" commit -qm base
mkimg "$R/img.png"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put tno img.png --name shot
{ [ $RC -eq 1 ] && [ ! -d "$R/.kit" ] && [ ! -d "$R/docs/verification" ]; } \
  && pass "no origin remote: exit 1, writes nothing" || fail "rc=$RC"

echo "== base url trailing slash =="
R="$TMP/rslash"; mkrepo "$R"; mkimg "$R/img.png"
run env KIT_CONFIG_OPERATOR="$TMP/op-slash" PROOF_ASSET_UPLOADER="$STUB/uploader.sh" \
  PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" bash "$BIN" put tsl img.png --name shot
printf '%s' "$OUT" | grep -qE '^!\[shot\]\(https://proof\.test/acme/' \
  && pass "a trailing slash on the base yields no double slash" || fail "url: $OUT"

echo "== --name keeps every dot (settings.v2 stays settings.v2) =="
R="$TMP/rname"; mkrepo "$R"; mkimg "$R/img.png"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put tnm img.png --name settings.v2
printf '%s' "$(mfile tnm)" | grep -qE '^settings\.v2-[0-9a-f]{8}\.webp$' \
  && pass "settings.v2 survives into the file name" || fail "file=$(mfile tnm)"

echo "== put distrusts a bad committed manifest =="
R="$TMP/rbadm"; mkrepo "$R"; mkimg "$R/img.png"
mkdir -p "$R/docs/verification/tbm"
printf '{"slug":"tbm","rand":"NOTHEX","assets":[]}\n' > "$(manifest tbm)"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put tbm img.png --name shot
{ [ $RC -eq 0 ] && printf '%s' "$ERR" | grep -qi 'rand' \
  && [ "$(jq -r '.rand' "$(manifest tbm)")" != "NOTHEX" ] \
  && printf '%s' "$(jq -r '.rand' "$(manifest tbm)")" | grep -qE '^[0-9a-f]{32}$'; } \
  && pass "a bad manifest rand warns and is replaced" || fail "rc=$RC rand=$(jq -r '.rand' "$(manifest tbm)" 2>/dev/null)"
R="$TMP/rbada"; mkrepo "$R"; mkimg "$R/img.png"
mkdir -p "$R/docs/verification/tba"
printf '{"slug":"tba","rand":"0123456789abcdef0123456789abcdef","assets":{"shot":{}}}\n' > "$(manifest tba)"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put tba img.png --name shot
{ [ $RC -ne 0 ] && printf '%s' "$ERR" | grep -qi 'assets' \
  && [ "$(jq -r '.assets | type' "$(manifest tba)")" = object ]; } \
  && pass "a non-array .assets refuses, manifest untouched" || fail "rc=$RC"

echo "== flush distrusts the queue and the manifest =="
R="$TMP/revil"; mkrepo "$R"
mkdir -p "$R/docs/verification/evil" "$R/.kit/proof-assets/evil"
printf '{"slug":"evil","rand":"0123456789abcdef0123456789abcdef","assets":[]}\n' \
  > "$R/docs/verification/evil/assets.json"
printf 'secret-do-not-upload\n' > "$TMP/outside.txt"
printf '../../../../outside.txt\n' > "$(queue evil)"
: > "$UP_LOG"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush
{ [ $RC -eq 0 ] && ! grep -q 'outside' "$UP_LOG" && printf '%s' "$ERR" | grep -qi 'unsafe\|invalid\|refus'; } \
  && pass "a traversal queue line is warned, dropped, never uploaded" \
  || fail "rc=$RC up=$(cat "$UP_LOG") err=[$ERR]"
[ ! -f "$(queue evil)" ] && pass "the bad line leaves the queue" || fail "queue kept the bad line"
mkdir -p "$R/docs/verification/badrand" "$R/.kit/proof-assets/badrand"
printf '{"slug":"badrand","rand":"ZZZ","assets":[]}\n' > "$R/docs/verification/badrand/assets.json"
printf 'x' > "$R/.kit/proof-assets/badrand/shot-01234567.webp"
printf 'shot-01234567.webp\n' > "$(queue badrand)"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush badrand
{ [ $RC -eq 1 ] && [ -s "$(queue badrand)" ] && printf '%s' "$ERR" | grep -qi 'rand\|invalid'; } \
  && pass "a bad manifest rand blocks the flush, queue kept" || fail "rc=$RC err=[$ERR]"
mkdir -p "$R/docs/verification/mismatch" "$R/.kit/proof-assets/mismatch"
printf '{"slug":"other","rand":"0123456789abcdef0123456789abcdef","assets":[]}\n' \
  > "$R/docs/verification/mismatch/assets.json"
printf 'x' > "$R/.kit/proof-assets/mismatch/shot-01234567.webp"
printf 'shot-01234567.webp\n' > "$(queue mismatch)"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush mismatch
{ [ $RC -eq 1 ] && [ -s "$(queue mismatch)" ]; } \
  && pass "a manifest slug that fights its dir blocks the flush" || fail "rc=$RC err=[$ERR]"

echo "== a still no encoder can convert must not land as a copy =="
R="$TMP/rnoenc"; mkrepo "$R"; { printf '\xff\xd8\xff\xe0'; head -c 1000 /dev/zero; } > "$R/img.jpg"
run env PATH="$STUB/noenc:$PATH" PROOF_ASSET_CONVERT="$STUB/conv-fail.sh" \
  PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" put tnc img.jpg --name shot
{ [ $RC -eq 2 ] && [ ! -f "$(manifest tnc)" ]; } \
  && pass "unconvertible still: exit 2, no manifest" || fail "rc=$RC"
if command -v sips >/dev/null 2>&1; then
  R="$TMP/rsips"; mkrepo "$R"; mkrealpng "$R/real.png"
  sips -s format jpeg "$R/real.png" --out "$R/real.jpg" >/dev/null 2>&1
  run env PATH="$STUB/nocwebp:$PATH" PROOF_ASSET_CONVERT="$STUB/conv-fail.sh" \
    PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" put tsp real.jpg --name shot
  { [ $RC -eq 0 ] && printf '%s' "$(mfile tsp)" | grep -qE '\.png$'; } \
    && pass "sips is the last encoder: jpeg -> .png" || fail "rc=$RC file=$(mfile tsp) err=[$ERR]"
fi

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
printf '%s' "$OUT" | grep -qE '^!\[shot\]\(\.kit/proof-assets/tloc/shot-[0-9a-f]{8}\.webp\)$' \
  && pass "local mode prints the cache-path embed" || fail "paste line: $OUT"

echo "== round trip: offline put, commit, flush -> the tree lands clean =="
R="$TMP/rland"; mkrepo "$R"; mkimg "$R/img.png"; : > "$UP_FAIL"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" PROOF_ASSET_CONVERT="$STUB/conv-webp.sh" \
  bash "$BIN" put trt img.png --name shot
( cd "$R" && git add -A && git commit -qm "docs: proof" )
rm -f "$UP_FAIL"
run env PROOF_ASSET_UPLOADER="$STUB/uploader.sh" bash "$BIN" flush
{ [ $RC -eq 0 ] && printf '%s' "$OUT" | grep -qE '^!\[shot\]\(https://proof\.test/'; } \
  && pass "the queued put flushes once the uploader is back" || fail "flush rc=$RC out=[$OUT]"
PORC="$(cd "$R" && git status --porcelain)"
[ -z "$PORC" ] && pass "git status --porcelain is empty after the flush" || fail "dirty: $PORC"
IGN="$(cd "$R" && git status --porcelain --ignored=matching | grep -v '^!! ')"
[ -z "$IGN" ] && pass "only ignored cache lines remain: land's dirty check would pass" || fail "non-ignored: $IGN"

echo "== usage and outside-a-repo guards =="
OUT="$(bash "$BIN" 2>&1)"; RC=$?
{ [ $RC -eq 64 ] && printf '%s' "$OUT" | grep -q 'usage: proof-asset'; } && pass "no args -> usage, exit 64" || fail "rc=$RC out=[$OUT]"
R="$TMP/notrepo"; rm -rf "$R"; mkdir -p "$R"
run bash "$BIN" put x f.png
{ [ $RC -ne 0 ] && printf '%s' "$ERR" | grep -qi 'repo'; } && pass "outside a git repo -> nonzero, says why" || fail "rc=$RC err=[$ERR]"

echo "---"
[ "$fails" -eq 0 ] && { echo "ALL PASS"; exit 0; } || { echo "FAILS: $fails"; exit 1; }
