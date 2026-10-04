#!/usr/bin/env bash
# test-proof-visual-gate.sh -- the opt-in image rule in proof-ledger.sh check (R1-R4).
# Off by default: with [proof] visual unset/false every case is byte-identical to master.
# On, a behavioral diff touching a UI extension (.tsx .jsx .vue .svelte .css .scss .html)
# owes ONE qualifying image on top of every existing rule:
#   R3a  a changed docs/verification/<dir>/assets.json entry whose bucket-prefixed url
#        (no '..' / '%', declared bytes under the cap, at most 5 fetches per check) is
#        embedded in a changed proof file and whose fetched bytes hash to its sha256
#   R3b  an image link in a changed proof file whose target git ls-files lists AND is
#        in the branch's own changed files
#   R3c  a `status: local` entry whose cached file exists -- only when a TRACKED, CLEAN
#        project .kit.toml sets assets = "local" (and slug/file pass the write-time
#        regexes before either joins a path)
# Block messages name the case: no image / fetch failed / hash mismatch /
# url outside the proof bucket / run `bin/proof-asset flush` for pending entries.
#
# No case touches the network: PROOF_ASSET_FETCH is a stub everywhere (a fail stub by
# default, a fixture-cat stub where the bytes matter). module under test:
# lib/gate/proof-ledger.sh check
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LIB="$KIT/lib/gate/proof-ledger.sh"
fails=0; total=0
pass(){ total=$((total+1)); echo "PASS $*"; }
fail(){ total=$((total+1)); echo "FAIL $*"; fails=$((fails+1)); }

TMPD="$(mktemp -d "${TMPDIR:-/tmp}/dk-proof-vg.XXXXXX")"
trap 'rm -rf "$TMPD"' EXIT
export GIT_TEMPLATE_DIR="$TMPD/no-git-template"; mkdir -p "$GIT_TEMPLATE_DIR"
export KIT_LEDGER_DIR="$TMPD/ledger"
# The config layers a stray host file could never reach: kit-root is the repo under test
# (its kit.toml ships the [proof] defaults), the operator layer is a fixture dir that
# carries ONLY the owner routing table (read root-only, a project file never sees it).
export KIT_CONFIG_ROOT="$KIT"
export KIT_CONFIG_OPERATOR="$TMPD/op"
mkdir -p "$TMPD/op"
cat > "$TMPD/op/kit.toml" <<'TOML'
[proof]
base_url_tieubao = "https://proof.han.ws"
base_url_dwarvesf = "https://proof.d.foundation"
TOML
# The fetch seam: fail closed by default so an unexpected fetch can never reach curl.
export PROOF_ASSET_FETCH="$TMPD/fetch-fail"
printf '#!/bin/sh\nexit 1\n' > "$PROOF_ASSET_FETCH"; chmod +x "$PROOF_ASSET_FETCH"

# new_repo <name> -- one base commit, origin = git@github.com:tieubao/widget.git so the
# owner/repo the gate derives is tieubao/widget and the bucket prefix is
# https://proof.han.ws/tieubao/widget/ (base from the operator fixture above).
new_repo() {
  local d="$TMPD/$1"
  mkdir -p "$d/docs/verification" "$d/lib" "$d/app"
  git -C "$d" init -q; git -C "$d" config user.email t@t; git -C "$d" config user.name t
  git -C "$d" config commit.gpgsign false
  git -C "$d" remote add origin git@github.com:tieubao/widget.git
  echo "# Verification log (proof of done)" > "$d/docs/verification/README.md"
  echo baseline > "$d/lib/thing.sh"
  git -C "$d" add -A; git -C "$d" commit -qm base
  printf '%s\n' "$d"
}
# ui_diff <repo> -- a changed UI file (untracked counts: _changed reads the worktree too)
ui_diff() { mkdir -p "$1/app"; echo "export default function P() {}" > "$1/app/page.tsx"; }
# proof_ok <repo> -- a passing behavioral proof (green run + captured output + NEGATIVE
# CONTROL, final verdict PASS); extra lines on stdin are appended (image embeds go there)
proof_ok() {
  { echo "# Verification"
    echo "## NEGATIVE CONTROL"
    echo "reverting the change turns this RED."
    echo "Command: \`bash lib/thing.sh\`"
    echo "Exit: 0"
    echo "Output:"
    echo "test-thing: all 3 passed"
    echo "Verdict: PASS"
    cat
  } > "$1/docs/verification/vf.md"
}
# manifest <repo> <status> <url> <sha> [bytes] -- a changed docs/verification/ui/assets.json
manifest() {
  mkdir -p "$1/docs/verification/ui"
  cat > "$1/docs/verification/ui/assets.json" <<EOF
{"slug":"ui","rand":"0123456789abcdef0123456789abcdef","assets":[{"name":"shot","file":"shot.webp","status":"$2","url":"$3","sha256":"$4","bytes":${5:-12}}]}
EOF
}
# The project layer only counts when .kit.toml is tracked and clean, so the fixtures
# commit the opt-in; cases that exercise an uncommitted file write it raw instead.
visual_on() { printf '[proof]\nvisual = true\n' > "$1/.kit.toml"; git -C "$1" add .kit.toml; git -C "$1" commit -qm "config: visual on"; }
local_on()  { printf '[proof]\nvisual = true\nassets = "local"\n' > "$1/.kit.toml"; }

gate(){ bash "$LIB" check "$1" "$(git -C "$1" rev-parse HEAD)" vf 2>&1; }
accepts(){ if gate "$2" >/dev/null 2>&1; then pass "$1"; else fail "$1 (BLOCKED, want ACCEPT)"; fi; }
blocks(){ if gate "$2" >/dev/null 2>&1; then fail "$1 (ACCEPTED, want BLOCK)"; else pass "$1"; fi; }
msg_has(){ local out; out="$(gate "$2")"; case "$out" in *"$3"*) pass "$1" ;; *) fail "$1 (missing '$3' in: $out)" ;; esac; }
fetch_ok(){ # fetch_ok <repo> <fixture-file> <tag>: stub PROOF_ASSET_FETCH to emit <fixture-file>
  printf '#!/bin/sh\ncat "%s"\n' "$2" > "$TMPD/fetch-$3-$$"; chmod +x "$TMPD/fetch-$3-$$"
  PROOF_ASSET_FETCH="$TMPD/fetch-$3-$$" gate "$1" >/dev/null 2>&1
}

RAND="0123456789abcdef0123456789abcdef"
URL="https://proof.han.ws/tieubao/widget/ui/$RAND/shot.webp"

echo "=== case 1: R1 off, UI diff, text-only proof passes exactly as on master ==="
D="$(new_repo c1)"; ui_diff "$D"; proof_ok "$D" </dev/null
accepts "case 1: off, UI diff + text-only proof" "$D"

echo "=== case 2: R1 on, UI diff, text-only proof is BLOCKED naming 'no image' ==="
D="$(new_repo c2)"; visual_on "$D"; ui_diff "$D"; proof_ok "$D" </dev/null
blocks "case 2: on, UI diff + text-only proof" "$D"
msg_has "case 2: the block says 'no image'" "$D" "no image"

echo "=== case 3: R3a entry, fetch returns matching bytes, link in proof -> passes ==="
D="$(new_repo c3)"; visual_on "$D"; ui_diff "$D"
IMG="$TMPD/c3.webp"; printf 'webp-bytes-c3' > "$IMG"
SHA="$(shasum -a 256 "$IMG" | awk '{print $1}')"
manifest "$D" uploaded "$URL" "$SHA"
printf '![shot](%s)\n' "$URL" | proof_ok "$D"
if fetch_ok "$D" "$IMG" c3; then pass "case 3: verified uploaded asset passes"; else fail "case 3 (BLOCKED, want ACCEPT): $(gate "$D")"; fi

echo "=== case 4: R3a entry, fetched bytes differ -> BLOCKED 'hash mismatch' ==="
D="$(new_repo c4)"; visual_on "$D"; ui_diff "$D"
manifest "$D" uploaded "$URL" "$SHA"
printf '![shot](%s)\n' "$URL" | proof_ok "$D"
printf '#!/bin/sh\nprintf "different-bytes"\n' > "$TMPD/fetch-bad4"; chmod +x "$TMPD/fetch-bad4"
if OUT="$(PROOF_ASSET_FETCH="$TMPD/fetch-bad4" gate "$D")"; then fail "case 4 (ACCEPTED, want BLOCK)"; else pass "case 4: mismatched bytes blocked"; fi
case "$OUT" in *"hash mismatch: $URL"*) pass "case 4: the block names 'hash mismatch: <url>'" ;; *) fail "case 4 message: $OUT" ;; esac

echo "=== case 5: queued entry (the .pending file) + fetch fails -> 'fetch failed' AND 'bin/proof-asset flush' ==="
D="$(new_repo c5)"; visual_on "$D"; ui_diff "$D"
manifest "$D" r2 "$URL" "$SHA"
mkdir -p "$D/.kit/proof-assets/ui"; printf 'shot.webp\n' > "$D/.kit/proof-assets/ui/.pending"
printf '![shot](%s)\n' "$URL" | proof_ok "$D"
blocks "case 5: queued entry whose fetch fails" "$D"
msg_has "case 5: the block names 'fetch failed: <url>'" "$D" "fetch failed: $URL"
msg_has "case 5: the block says to run 'bin/proof-asset flush'" "$D" 'bin/proof-asset flush'

echo "=== case 6: assets=local from a tracked, clean .kit.toml + cached file -> passes ==="
D="$(new_repo c6)"
local_on "$D"; git -C "$D" add .kit.toml; git -C "$D" commit -qm "config: opt in"
ui_diff "$D"
mkdir -p "$D/.kit/proof-assets/ui"; printf 'local-bytes' > "$D/.kit/proof-assets/ui/shot.webp"
manifest "$D" local "" ""
proof_ok "$D" </dev/null
accepts "case 6: local asset with cached file passes" "$D"

echo "=== case 7: a committed (ls-files-listed) image linked in the proof -> passes ==="
D="$(new_repo c7)"; visual_on "$D"; ui_diff "$D"
printf 'GIF89a' > "$D/docs/verification/shot.gif"
git -C "$D" add docs/verification/shot.gif
printf '![after](shot.gif)\n' | proof_ok "$D"
accepts "case 7: tracked image embed passes" "$D"

echo "=== case 8: stateful diff touching a UI file gets no image rule ==="
D="$(new_repo c8)"; visual_on "$D"; ui_diff "$D"
mkdir -p "$D/deploy"; echo "rollout v2" > "$D/deploy/rollout.sh"
{ echo "# Verification"; echo "rollback: git revert HEAD"
  echo "Command: \`bash deploy/rollout.sh --dry-run\`"; echo "Exit: 0"
  echo "Output:"; echo "dry-run: 3 hosts would roll"; } > "$D/docs/verification/vf.md"
accepts "case 8: stateful + UI file, text-only proof passes" "$D"

echo "=== case 9: assets=local only in an UNCOMMITTED .kit.toml -> R3c refused ==="
# visual = true rides the operator layer here, so the rule is on while the project's
# local opt-in stays untracked (tracked_clean fails): the local path must not unlock.
mkdir -p "$TMPD/op-visual"
cat > "$TMPD/op-visual/kit.toml" <<'TOML'
[proof]
visual = true
base_url_tieubao = "https://proof.han.ws"
TOML
D="$(new_repo c9)"; local_on "$D"; ui_diff "$D"   # .kit.toml stays untracked
mkdir -p "$D/.kit/proof-assets/ui"; printf 'local-bytes' > "$D/.kit/proof-assets/ui/shot.webp"
manifest "$D" local "" ""
proof_ok "$D" </dev/null
if KIT_CONFIG_OPERATOR="$TMPD/op-visual" gate "$D" >/dev/null 2>&1; then
  fail "case 9: untracked .kit.toml unlocked the local path (ACCEPTED, want BLOCK)"
else
  pass "case 9: untracked .kit.toml cannot unlock the local path"
fi

echo "=== case 10: entry url outside <base>/<owner>/<repo>/ -> named so ==="
D="$(new_repo c10)"; visual_on "$D"; ui_diff "$D"
BAD="https://proof.han.ws/tieubao/other/ui/$RAND/shot.webp"
manifest "$D" uploaded "$BAD" "$SHA"
printf '![shot](%s)\n' "$BAD" | proof_ok "$D"
blocks "case 10: url outside the proof bucket" "$D"
msg_has "case 10: the block names 'url outside the proof bucket: <url>'" "$D" "url outside the proof bucket: $BAD"

echo "=== case 11: image link to a gitignored file under .kit/proof-assets/ is not R3b ==="
D="$(new_repo c11)"; visual_on "$D"; ui_diff "$D"
printf '.kit/proof-assets/\n' > "$D/.gitignore"
mkdir -p "$D/.kit/proof-assets/ui"; printf 'GIF89a' > "$D/.kit/proof-assets/ui/shot.gif"
printf '![shot](.kit/proof-assets/ui/shot.gif)\n' | proof_ok "$D"
blocks "case 11: a gitignored target does not count" "$D"

echo "=== case 12: a non-UI code file alone is not visual ==="
D="$(new_repo c12)"; visual_on "$D"
mkdir -p "$D/app/models"; echo "class User; end" > "$D/app/models/user.rb"
proof_ok "$D" </dev/null
accepts "case 12: app/models/user.rb only, text-only proof passes" "$D"

echo "=== case 13: an R3a url holding '..' or '%' is refused, prefix or not ==="
D="$(new_repo c13a)"; visual_on "$D"; ui_diff "$D"
BAD="https://proof.han.ws/tieubao/widget/../other/ui/$RAND/shot.webp"
manifest "$D" r2 "$BAD" "$SHA"
printf '![shot](%s)\n' "$BAD" | proof_ok "$D"
blocks "case 13a: '..' inside a bucket-prefixed url" "$D"
msg_has "case 13a: the block names the unsafe url" "$D" "unsafe url: $BAD"
D="$(new_repo c13b)"; visual_on "$D"; ui_diff "$D"
BAD="https://proof.han.ws/tieubao/widget/ui/$RAND/%2e%2e/shot.webp"
manifest "$D" r2 "$BAD" "$SHA"
printf '![shot](%s)\n' "$BAD" | proof_ok "$D"
blocks "case 13b: '%' inside the url" "$D"
msg_has "case 13b: the block names the unsafe url" "$D" "unsafe url: $BAD"

echo "=== case 14: declared bytes over the 3 MB cap is refused before any fetch ==="
D="$(new_repo c14)"; visual_on "$D"; ui_diff "$D"
manifest "$D" r2 "$URL" "$SHA" 4000000
printf '![shot](%s)\n' "$URL" | proof_ok "$D"
FETCHLOG="$TMPD/fetch-calls-14"; : > "$FETCHLOG"
printf '#!/bin/sh\necho called >> "%s"\nexit 1\n' "$FETCHLOG" > "$TMPD/fetch-spy"; chmod +x "$TMPD/fetch-spy"
if PROOF_ASSET_FETCH="$TMPD/fetch-spy" gate "$D" >/dev/null 2>&1; then
  fail "case 14: over-cap entry (ACCEPTED, want BLOCK)"
elif [ -s "$FETCHLOG" ]; then
  fail "case 14: the entry was fetched despite a declared size over the cap"
else
  pass "case 14: over-cap entry refused with no fetch"
fi

echo "=== case 15: at most 5 fetches per check ==="
D="$(new_repo c15)"; visual_on "$D"; ui_diff "$D"
FETCHLOG="$TMPD/fetch-calls-15"; : > "$FETCHLOG"
printf '#!/bin/sh\necho called >> "%s"\nexit 1\n' "$FETCHLOG" > "$TMPD/fetch-spy-15"; chmod +x "$TMPD/fetch-spy-15"
mkdir -p "$D/docs/verification/ui"
{ printf '{"slug":"ui","rand":"%s","assets":[' "$RAND"
  for i in 1 2 3 4 5 6 7; do
    [ "$i" -gt 1 ] && printf ','
    printf '{"name":"s%s","file":"s%s.webp","status":"r2","url":"%s","sha256":"%s","bytes":12}' \
      "$i" "$i" "https://proof.han.ws/tieubao/widget/ui/$RAND/s$i.webp" "$SHA"
  done
  printf ']}' ; } > "$D/docs/verification/ui/assets.json"
{ for i in 1 2 3 4 5 6 7; do printf '![s%s](https://proof.han.ws/tieubao/widget/ui/%s/s%s.webp)\n' "$i" "$RAND" "$i"; done; } | proof_ok "$D"
if PROOF_ASSET_FETCH="$TMPD/fetch-spy-15" gate "$D" >/dev/null 2>&1; then
  fail "case 15: seven unverifiable entries (ACCEPTED, want BLOCK)"
else
  N="$(wc -l < "$FETCHLOG" | tr -d ' ')"
  [ "$N" -le 5 ] && pass "case 15: fetch count capped at 5 (saw $N)" || fail "case 15: $N fetches, cap is 5"
fi

echo "=== case 16: an old tracked image unchanged by the branch is not R3b ==="
D="$(new_repo c16)"; visual_on "$D"
mkdir -p "$D/public"; printf 'GIF89a' > "$D/public/logo.png"
git -C "$D" add -A; git -C "$D" commit -qm "add logo"      # tracked at base, not in this diff
ui_diff "$D"
printf '![logo](public/logo.png)\n' | proof_ok "$D"
blocks "case 16: a tracked image the branch did not change does not count" "$D"

echo "=== case 17: R3c refuses a traversal slug or file before the -f test ==="
D="$(new_repo c17a)"; local_on "$D"
git -C "$D" add .kit.toml; git -C "$D" commit -qm "config: local opt-in"
ui_diff "$D"
mkdir -p "$D/.kit/proof-assets" "$D/docs/verification/ui"
printf 'local-bytes' > "$D/.kit/proof-assets/escape.webp"
cat > "$D/docs/verification/ui/assets.json" <<EOF
{"slug":"ui","rand":"$RAND","assets":[{"name":"shot","file":"../escape.webp","status":"local","url":"","sha256":"","bytes":12}]}
EOF
proof_ok "$D" </dev/null
blocks "case 17a: file '../escape.webp' must not resolve outside the cache" "$D"
D="$(new_repo c17b)"; local_on "$D"
git -C "$D" add .kit.toml; git -C "$D" commit -qm "config: local opt-in"
ui_diff "$D"
mkdir -p "$D/.kit" "$D/docs/verification/x"
printf 'local-bytes' > "$D/.kit/escape.webp"
cat > "$D/docs/verification/x/assets.json" <<EOF
{"slug":"..","rand":"$RAND","assets":[{"name":"shot","file":"escape.webp","status":"local","url":"","sha256":"","bytes":12}]}
EOF
proof_ok "$D" </dev/null
blocks "case 17b: slug '..' must not resolve outside the cache" "$D"

echo "=== case 18: an uncommitted .kit.toml cannot disarm an operator opt-in ==="
mkdir -p "$TMPD/op-visual"
cat > "$TMPD/op-visual/kit.toml" <<'TOML'
[proof]
visual = true
base_url_tieubao = "https://proof.han.ws"
TOML
D="$(new_repo c18)"
printf '[proof]\nvisual = false\n' > "$D/.kit.toml"    # untracked: tracked_clean fails
ui_diff "$D"; proof_ok "$D" </dev/null
if KIT_CONFIG_OPERATOR="$TMPD/op-visual" gate "$D" >/dev/null 2>&1; then
  fail "case 18: an untracked .kit.toml disarmed the operator's visual = true"
else
  pass "case 18: an untracked .kit.toml cannot disarm the operator opt-in"
fi
D="$(new_repo c18b)"
printf '[proof]\nvisual = false\n' > "$D/.kit.toml"
git -C "$D" add .kit.toml; git -C "$D" commit -qm "config: opt out"
ui_diff "$D"; proof_ok "$D" </dev/null
if KIT_CONFIG_OPERATOR="$TMPD/op-visual" gate "$D" >/dev/null 2>&1; then
  pass "case 18b: a committed clean .kit.toml still disarms (auditable opt-out)"
else
  fail "case 18b: a committed opt-out should hold (BLOCKED, want ACCEPT)"
fi

echo "=== case 19: an audited override clears the visual block like the proof block ==="
D="$(new_repo c19)"; visual_on "$D"
echo "body { color: red }" > "$D/app/site.css"       # .css: not a source-code remainder
proof_ok "$D" </dev/null
blocks "case 19: no image, no override -> blocked" "$D"
( cd "$D" && bash "$LIB" override vf "battery: audited visual override" >/dev/null 2>&1 )
if gate "$D" >/dev/null 2>&1; then
  pass "case 19: a logged override clears the visual block"
else
  fail "case 19: the override should clear the visual block (BLOCKED, want ACCEPT)"
fi
D="$(new_repo c19b)"; visual_on "$D"
ui_diff "$D"; proof_ok "$D" </dev/null               # .tsx IS a source-code remainder
( cd "$D" && bash "$LIB" override vf "battery: audited visual override" >/dev/null 2>&1 )
blocks "case 19b: the override still rejects a source remainder (.tsx)" "$D"

echo
[ "$fails" -eq 0 ] && { echo "test-proof-visual-gate: all $total passed"; exit 0; } \
                  || { echo "test-proof-visual-gate: $fails FAILED of $total"; exit 1; }
