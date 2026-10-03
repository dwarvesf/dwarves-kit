#!/usr/bin/env bash
# asset.sh -- lib/proof: the proof-asset pipeline behind bin/proof-asset.
#
# WHY: a visual proof needs an image a reviewer can open. Committing images grows the
# repo forever, so assets go to a bucket behind an unguessable key: <owner>/<repo>/
# <slug>/<rand>/<name>-<sha8>.<ext>, where <rand> is 32 hex chars generated once per
# slug and stored in the manifest and <sha8> is the first 8 hex of the asset's own
# sha256, so a re-put under one name can never serve stale edge-cached bytes. The repo
# keeps only the committed manifest (docs/verification/<slug>/assets.json); the bytes
# sit in the gitignored local cache (.kit/proof-assets/<slug>/), where a self-written
# .gitignore ("*") keeps the cache untracked in any repo, kit or not.
#
# The committed manifest never records upload state: put writes each entry's final
# url, sha256, bytes, and status = "r2" or "local" (the DESTINATION, not progress).
# Upload progress lives only in the gitignored queue .kit/proof-assets/<slug>/.pending
# (one file name per line): a failed or impossible put appends its file name there,
# flush uploads each queued file, drops the line on success, and exits 1 while any
# line remains. A successful flush therefore leaves the worktree clean enough for
# `wrap land`, which refuses on a dirty tree.
#
# put: convert + cap (a still becomes WebP, or an optimized PNG when no WebP encoder
# answers -- sips on macOS is the last encoder, and a still no encoder can convert
# refuses with exit 2 rather than landing a raw copy -- at most 300 KB; a GIF stays
# GIF, at most 2 MB), sha256, cache, manifest upsert keyed by entry name, upload when
# proof.assets resolves to "r2". With proof.assets = "local" nothing ever uploads.
# With assets = "r2" and no usable route (no origin remote, no proof.base_url_<owner>
# in the operator kit.toml) put refuses with exit 1 and writes nothing, because the
# embed it would print could never verify at the gate.
#
# The manifest and the queue are untrusted input (a committed manifest rides a PR):
# slug, rand, .assets, and every file name are validated before they touch the
# filesystem or an upload, so a crafted file field can never read outside the cache.
#
# The credential never reaches stdout, stderr, a file, or a commit. The uploader reads
# it at call time: wrangler's own login, or proof.asset_token_ref (a root-only key)
# resolved through secret-cache-read into the wrangler call's own environment.
#
# Seams (tests set these; nothing here touches the network by itself):
#   PROOF_ASSET_UPLOADER   <cmd> <local-file> <key> <account-id>
#                          default: CLOUDFLARE_ACCOUNT_ID=<id> wrangler r2 object put
#                          "<bucket>/<key>" --file <local-file> --remote
#   PROOF_ASSET_CONVERT    <cmd> <in> <out>
#                          default: cwebp -q 80, else pngquant, else sips ->png
#
# Exit codes: 0 done or queued; 1 flush with entries still pending, or operational
# error; 2 over the byte cap after conversion or no working encoder (the message
# names the measured size); 64 usage.
set -euo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$KIT_DIR/lib/config/kit-config.sh"

usage() {
  echo "usage: proof-asset put <slug> <file> [--name N]" >&2
  echo "       proof-asset flush [<slug>]" >&2
  exit 64
}

_slugify() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | tr '/ ' '--' | tr -cd 'a-z0-9._-'; }

# The trust rules for everything read back out of a committed manifest or a queue file.
_valid_slug() { printf '%s' "$1" | grep -qE '^[a-z0-9][a-z0-9._-]*$'; }
_valid_rand() { printf '%s' "$1" | grep -qE '^[0-9a-f]{32}$'; }
_valid_file() { printf '%s' "$1" | grep -qE '^[a-z0-9][a-z0-9._-]*\.(webp|png|gif|jpg)$'; }

_repo_root() {
  local r
  r="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "proof-asset: not inside a git repo" >&2; exit 1; }
  printf '%s' "$r"
}

# _owner_repo <root> -> "<owner> <repo>" from the origin remote, lowercased. The last
# two path parts, .git stripped: git@github.com:o/r.git and https://github.com/o/r
# resolve the same. Empty output when no origin or it does not parse.
_owner_repo() {
  local remote r o p
  remote="$(git -C "$1" remote get-url origin 2>/dev/null)" || return 1
  remote="${remote%.git}"; remote="${remote%/}"
  case "$remote" in
    *://*) p="${remote#*://}" ;;      # scheme form: host/path...
    *)     p="${remote/:/\/}" ;;      # scp form: the first : separates host from path
  esac
  r="${p##*/}"; o="${p%/*}"; o="${o##*/}"
  [ -n "$o" ] && [ -n "$r" ] || return 1
  printf '%s %s' "$(printf '%s' "$o" | tr '[:upper:]' '[:lower:]')" \
                 "$(printf '%s' "$r" | tr '[:upper:]' '[:lower:]')"
}

# _sniff_ext <file> -> webp|png|gif|jpg|bin from magic bytes (never the filename).
_sniff_ext() {
  local h
  h="$(head -c 12 "$1" 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  case "$h" in
    89504e47*)                 echo png ;;
    47494638*)                 echo gif ;;
    ffd8ff*)                   echo jpg ;;
    52494646????????57454250*) echo webp ;;  # RIFF + 4 size bytes + WEBP
    *)                         echo bin ;;
  esac
}

# _convert <in> <out> -- seam first, then cwebp, then pngquant (PNG input only), then
# sips ->png (the macOS encoder of last resort). An input that already sniffs webp or
# png still satisfies R8 as a straight copy. Anything else (a JPEG no encoder can
# read) fails: the caller exits 2, because a still must land as WebP or PNG, never a
# raw pass-through.
_convert() {
  local in="$1" out="$2"
  if [ -n "${PROOF_ASSET_CONVERT:-}" ]; then
    $PROOF_ASSET_CONVERT "$in" "$out" && [ -s "$out" ] && return 0
  elif command -v cwebp >/dev/null 2>&1; then
    cwebp -q 80 "$in" -o "$out" >/dev/null 2>&1 && [ -s "$out" ] && return 0
  elif command -v pngquant >/dev/null 2>&1 && [ "$(_sniff_ext "$in")" = png ]; then
    pngquant --force --output "$out" "$in" >/dev/null 2>&1 && [ -s "$out" ] && return 0
  fi
  if command -v sips >/dev/null 2>&1; then
    sips -s format png "$in" --out "$out" >/dev/null 2>&1 && [ -s "$out" ] && return 0
  fi
  case "$(_sniff_ext "$in")" in
    webp|png) /bin/cp -f "$in" "$out"; return 0 ;;
  esac
  return 1
}

# _ref_tag <op-ref> -- 8 hex chars that name one ref's Keychain cache entry.
_ref_tag() { printf '%s' "$1" | shasum -a 256 | cut -c1-8; }

# _upload <local-file> <key> <account-id> -- the seam owns the whole call when set.
# Default: wrangler against the configured bucket, the token pulled at call time from
# the operator-level proof.asset_token_ref via secret-cache-read (Keychain-cached),
# falling back to wrangler's own login when no ref is configured. The token is passed
# INLINE on the wrangler call only, never exported into the process environment.
_upload() {
  local f="$1" key="$2" acct="$3" bucket tokref tok=""
  if [ -n "${PROOF_ASSET_UPLOADER:-}" ]; then
    $PROOF_ASSET_UPLOADER "$f" "$key" "$acct"
    return
  fi
  command -v wrangler >/dev/null 2>&1 || return 1
  bucket="$(kit_config_get_root proof.asset_bucket kit-proof-assets)"
  tokref="$(kit_config_get_root proof.asset_token_ref "")"
  # An operator file may hold the account as an op:// ref, so no account id sits in a repo.
  # The Keychain cache keys by name, so each ref gets its own name: a generic name would
  # return a value another tool cached under a different ref.
  case "$acct" in
    op://*) command -v secret-cache-read >/dev/null 2>&1 || return 1
            acct="$(secret-cache-read --ttl 86400 "PROOF_ASSET_ACCT_$(_ref_tag "$acct")" "$acct" 2>/dev/null)"
            [ -n "$acct" ] || return 1 ;;
  esac
  if [ -n "$tokref" ] && command -v secret-cache-read >/dev/null 2>&1; then
    tok="$(secret-cache-read --ttl 3600 "PROOF_ASSET_TOKEN_$(_ref_tag "$tokref")" "$tokref" 2>/dev/null)"
  fi
  if [ -n "$tok" ]; then
    CLOUDFLARE_API_TOKEN="$tok" CLOUDFLARE_ACCOUNT_ID="$acct" \
      wrangler r2 object put "$bucket/$key" --file "$f" --remote >/dev/null
  else
    CLOUDFLARE_ACCOUNT_ID="$acct" \
      wrangler r2 object put "$bucket/$key" --file "$f" --remote >/dev/null
  fi
}

# _manifest_put <mfile> <slug> <rand> <name> <file> <status> <url> <sha> <bytes> --
# create the manifest, or upsert the entry by name (a re-put keeps one entry).
_manifest_put() {
  local m="$1" t="$1.tmp.$$"; shift
  if [ -f "$m" ]; then
    jq --arg slug "$1" --arg rand "$2" --arg name "$3" --arg file "$4" \
       --arg status "$5" --arg url "$6" --arg sha "$7" --argjson bytes "$8" \
      '.slug = $slug | .rand = $rand
       | .assets = ((.assets // []) | map(select(.name != $name))
                    + [{name: $name, file: $file, status: $status, url: $url,
                        sha256: $sha, bytes: $bytes}])' \
      "$m" > "$t" || { rm -f "$t"; echo "proof-asset: unreadable manifest $m" >&2; return 1; }
  else
    jq -n --arg slug "$1" --arg rand "$2" --arg name "$3" --arg file "$4" \
       --arg status "$5" --arg url "$6" --arg sha "$7" --argjson bytes "$8" \
      '{slug: $slug, rand: $rand,
        assets: [{name: $name, file: $file, status: $status, url: $url,
                  sha256: $sha, bytes: $bytes}]}' \
      > "$t" || return 1
  fi
  /bin/mv -f "$t" "$m"
}

# The upload queue: <cache-dir>/.pending holds one file name per line.
_queue_add() { grep -qxF "$2" "$1/.pending" 2>/dev/null || printf '%s\n' "$2" >> "$1/.pending"; }
_queue_drop() {
  local q="$1" t="$1.tmp.$$"
  grep -vxF "$2" "$q" >| "$t" 2>/dev/null || :
  if [ -s "$t" ]; then /bin/mv -f "$t" "$q"; else rm -f "$t" "$q"; fi
}

cmd_put() {
  local slug file name="" root
  [ $# -ge 2 ] || usage
  slug="$1"; file="$2"; shift 2
  while [ $# -gt 0 ]; do
    case "$1" in
      --name) [ $# -ge 2 ] || usage; name="$2"; shift 2 ;;
      *) usage ;;
    esac
  done
  root="$(_repo_root)"
  [ -f "$file" ] || { echo "proof-asset: no such file: $file" >&2; exit 1; }
  export KIT_PROJECT_ROOT="$root"
  slug="$(_slugify "$slug")"
  _valid_slug "$slug" || { echo "proof-asset: invalid slug: $slug" >&2; exit 1; }
  # An explicit --name is kept verbatim (settings.v2 stays settings.v2); only the
  # default, file-derived name loses its last extension.
  if [ -z "$name" ]; then name="${file##*/}"; name="${name%.*}"; fi
  name="$(_slugify "$name")"
  [ -n "$name" ] || { echo "proof-asset: empty asset name" >&2; exit 64; }

  local mode; mode="$(kit_config_get proof.assets r2)"

  # The r2 route is resolved before anything is written: an upload that can never
  # route (no origin remote, no base url for the owner) exits 1 and leaves no files,
  # because the embed it would print could never verify at the gate.
  local or owner="" repo="" base="" acct=""
  or="$(_owner_repo "$root" || true)"
  owner="${or%% *}"; repo="${or##* }"
  [ "$or" = "$owner" ] && repo=""
  if [ "$mode" != local ]; then
    if [ -z "$owner" ] || [ -z "$repo" ]; then
      echo "proof-asset: no origin remote, cannot derive <owner>/<repo> for the upload route" >&2; exit 1
    fi
    base="$(kit_config_get_root "proof.base_url_$owner" "")"
    base="${base%/}"
    acct="$(kit_config_get_root "proof.account_$owner" "")"
    if [ -z "$base" ]; then
      echo "proof-asset: no proof.base_url_$owner in the operator kit.toml" >&2; exit 1
    fi
  fi

  local tmpd; tmpd="$(mktemp -d)"; trap "rm -rf '$tmpd'" EXIT

  # GIFs pass through untouched; every other still goes through the converter.
  local kind ext cap work
  kind="$(_sniff_ext "$file")"
  [ "$kind" = bin ] && kind="$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')"
  if [ "$kind" = gif ]; then
    work="$file"; ext=gif; cap=2097152
  else
    work="$tmpd/conv"
    _convert "$file" "$work" \
      || { echo "proof-asset: cannot convert $file to webp/png (no working encoder)" >&2; exit 2; }
    ext="$(_sniff_ext "$work")"
    [ "$ext" = bin ] && ext="$kind"
    cap=307200
  fi
  local bytes; bytes="$(wc -c < "$work" | tr -d ' ')"
  if [ "$bytes" -gt "$cap" ]; then
    echo "proof-asset: over cap: $bytes bytes (limit $cap)" >&2; exit 2
  fi

  local sha fname
  sha="$(shasum -a 256 "$work" | awk '{print $1}')"
  fname="$name-${sha:0:8}.$ext"
  _valid_file "$fname" || { echo "proof-asset: invalid asset name: $name" >&2; exit 1; }

  local cache_root="$root/.kit/proof-assets" cache_dir
  cache_dir="$cache_root/$slug"
  mkdir -p "$cache_dir" "$root/docs/verification/$slug"
  # The cache carries its own ignore rule: in a repo whose .gitignore never heard of
  # .kit, `git add -A` must still never pick up the image bytes or the queue.
  [ -f "$cache_root/.gitignore" ] || printf '*\n' > "$cache_root/.gitignore"
  /bin/cp -f "$work" "$cache_dir/$fname"

  local manifest="$root/docs/verification/$slug/assets.json" rand=""
  if [ -f "$manifest" ]; then
    rand="$(jq -r '.rand // empty' "$manifest" 2>/dev/null || true)"
    if [ -n "$rand" ] && ! _valid_rand "$rand"; then
      echo "proof-asset: ignoring invalid rand in $manifest; minting a fresh one" >&2
      rand=""
    fi
    if ! jq -e '.assets == null or (.assets | type) == "array"' "$manifest" >/dev/null 2>&1; then
      echo "proof-asset: manifest unreadable or .assets is not an array: $manifest" >&2; exit 1
    fi
  fi
  [ -n "$rand" ] || rand="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"

  local status queued=0 why="" key="" url=""
  if [ "$mode" = local ]; then
    status=local
  else
    status=r2
    key="$owner/$repo/$slug/$rand/$fname"; url="$base/$key"
    if [ -z "$acct" ]; then
      why="no proof.account_$owner in the operator kit.toml"
    elif _upload "$cache_dir/$fname" "$key" "$acct"; then
      :
    else
      why="upload failed or offline"
    fi
    if [ -n "$why" ]; then queued=1; _queue_add "$cache_dir" "$fname"; fi
  fi

  _manifest_put "$manifest" "$slug" "$rand" "$name" "$fname" "$status" "$url" "$sha" "$bytes"
  [ "$queued" -eq 1 ] \
    && printf 'queued: %s/%s (%s); run bin/proof-asset flush\n' "$slug" "$name" "$why" >&2
  if [ "$status" = local ]; then
    printf '![%s](.kit/proof-assets/%s/%s)\n' "$name" "$slug" "$fname"
  else
    printf '![%s](%s)\n' "$name" "$url"
  fi
}

cmd_flush() {
  local want="${1:-}"
  local root; root="$(_repo_root)"
  export KIT_PROJECT_ROOT="$root"
  local mode; mode="$(kit_config_get proof.assets r2)"

  local or owner="" repo="" base="" acct=""
  or="$(_owner_repo "$root" || true)"
  owner="${or%% *}"; repo="${or##* }"
  [ "$or" = "$owner" ] && repo=""
  [ -n "$owner" ] && base="$(kit_config_get_root "proof.base_url_$owner" "")"
  [ -n "$owner" ] && acct="$(kit_config_get_root "proof.account_$owner" "")"
  base="${base%/}"

  # The queue files are the whole story: the manifest is only ever READ (for rand and
  # the entry's name), never written, so a flush cannot dirty the worktree.
  local saw=0 failed=0 qdir queue mslug manifest rand mslug_json f name key url
  for qdir in "$root"/.kit/proof-assets/*/; do
    [ -d "$qdir" ] || continue
    queue="${qdir}.pending"
    [ -f "$queue" ] || continue
    mslug="$(basename "$qdir")"
    [ -n "$want" ] && [ "$mslug" != "$want" ] && continue
    saw=1
    if ! _valid_slug "$mslug"; then
      echo "flush: skipping unsafe cache dir name: $mslug" >&2; failed=1; continue
    fi
    manifest="$root/docs/verification/$mslug/assets.json"
    if [ ! -f "$manifest" ]; then
      echo "flush: $mslug: no manifest at docs/verification/$mslug/assets.json" >&2
      failed=1; continue
    fi
    rand="$(jq -r '.rand // empty' "$manifest" 2>/dev/null || true)"
    mslug_json="$(jq -r '.slug // empty' "$manifest" 2>/dev/null || true)"
    if [ "$mslug_json" != "$mslug" ] || ! _valid_rand "$rand" \
       || ! jq -e '.assets | type == "array"' "$manifest" >/dev/null 2>&1; then
      echo "flush: $mslug: manifest slug/rand/assets invalid; queue left pending" >&2
      failed=1; continue
    fi
    while IFS= read -r f; do
      [ -n "$f" ] || continue
      if ! _valid_file "$f"; then
        echo "flush: $mslug: refusing unsafe queue entry: $f" >&2
        _queue_drop "$queue" "$f"; continue
      fi
      if [ ! -f "$qdir$f" ]; then
        echo "still pending: $mslug/$f (no cached file)" >&2; failed=1; continue
      fi
      if [ "$mode" = local ]; then
        echo "flush: $mslug/$f: assets = \"local\" does not upload; re-run bin/proof-asset put" >&2
        _queue_drop "$queue" "$f"; continue
      fi
      if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$base" ] || [ -z "$acct" ]; then
        echo "still pending: $mslug/$f (no upload route: owner/base/account missing)" >&2
        failed=1; continue
      fi
      key="$owner/$repo/$mslug/$rand/$f"; url="$base/$key"
      if _upload "$qdir$f" "$key" "$acct"; then
        _queue_drop "$queue" "$f"
        name="$(jq -r --arg f "$f" '[.assets[]? | select(.file == $f) | .name] | first // empty' \
                "$manifest" 2>/dev/null)"
        if [ -z "$name" ]; then name="${f%.*}"; name="${name%-*}"; fi
        printf '![%s](%s)\n' "$name" "$url"
      else
        echo "still pending: $mslug/$f (upload failed)" >&2
        failed=1
      fi
    done < <(cat "$queue")   # snapshot: _queue_drop rewrites the file mid-loop
  done
  [ "$saw" -eq 0 ] && exit 0
  [ "$failed" -gt 0 ] && exit 1
  exit 0
}

cmd="${1:-}"
case "$cmd" in
  put)   shift; cmd_put "$@" ;;
  flush) shift; [ $# -le 1 ] || usage; cmd_flush "${1:-}" ;;
  *) usage ;;
esac
