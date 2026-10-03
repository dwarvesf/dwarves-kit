#!/usr/bin/env bash
# asset.sh -- lib/proof: the proof-asset pipeline behind bin/proof-asset.
#
# WHY: a visual proof needs an image a reviewer can open. Committing images grows the
# repo forever, so assets go to a bucket behind an unguessable key: <owner>/<repo>/
# <slug>/<rand>/<name>.<ext>, where <rand> is 32 hex chars generated once per slug and
# stored in the manifest. The repo keeps only the committed manifest
# (docs/verification/<slug>/assets.json); the bytes sit in the gitignored local cache
# (.kit/proof-assets/<slug>/).
#
# put: convert + cap (a still becomes WebP, or an optimized PNG when no WebP encoder
# answers, at most 300 KB; a GIF stays GIF, at most 2 MB), sha256, cache, manifest
# upsert keyed by entry name, upload when proof.assets resolves to "r2". A failed or
# impossible upload leaves the entry pending: exit is still 0 and one stderr line says
# "queued". flush retries every pending entry later, re-hashing the cached bytes, and
# exits 1 while any entry stays pending. With proof.assets = "local" nothing ever
# uploads: put writes status "local" and flush heals stale pending entries the same way.
#
# The credential never reaches stdout, stderr, a file, or a commit. The uploader reads
# it at call time: wrangler's own login, or proof.asset_token_ref (a root-only key)
# resolved through secret-cache-read into the wrangler environment.
#
# Seams (tests set these; nothing here touches the network by itself):
#   PROOF_ASSET_UPLOADER   <cmd> <local-file> <key> <account-id>
#                          default: CLOUDFLARE_ACCOUNT_ID=<id> wrangler r2 object put
#                          "<bucket>/<key>" --file <local-file> --remote
#   PROOF_ASSET_CONVERT    <cmd> <in> <out>
#                          default: cwebp -q 80, else pngquant, else a copy
#
# Exit codes: 0 done or queued; 1 flush with entries still pending, or operational
# error; 2 over the byte cap after conversion (the message names the measured size);
# 64 usage.
set -euo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$KIT_DIR/lib/config/kit-config.sh"

usage() {
  echo "usage: proof-asset put <slug> <file> [--name N]" >&2
  echo "       proof-asset flush [<slug>]" >&2
  exit 64
}

_slugify() { printf '%s' "$1" | tr '/ ' '--' | tr -cd '[:alnum:]._-'; }

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

# _convert <in> <out> -- seam first, then cwebp, then pngquant (PNG input only), else a
# straight copy. A converter that errors falls through to the copy: the byte cap, not
# the encoder, is what a too-big image dies on.
_convert() {
  local in="$1" out="$2"
  if [ -n "${PROOF_ASSET_CONVERT:-}" ]; then
    $PROOF_ASSET_CONVERT "$in" "$out" && [ -s "$out" ] && return 0
  elif command -v cwebp >/dev/null 2>&1; then
    cwebp -q 80 "$in" -o "$out" >/dev/null 2>&1 && [ -s "$out" ] && return 0
  elif command -v pngquant >/dev/null 2>&1 && [ "$(_sniff_ext "$in")" = png ]; then
    pngquant --force --output "$out" "$in" >/dev/null 2>&1 && [ -s "$out" ] && return 0
  fi
  /bin/cp -f "$in" "$out"
}

# _upload <local-file> <key> <account-id> -- the seam owns the whole call when set.
# Default: wrangler against the configured bucket, the token pulled at call time from
# the operator-level proof.asset_token_ref via secret-cache-read (Keychain-cached),
# falling back to wrangler's own login when no ref is configured.
_upload() {
  local f="$1" key="$2" acct="$3" bucket tokref
  if [ -n "${PROOF_ASSET_UPLOADER:-}" ]; then
    $PROOF_ASSET_UPLOADER "$f" "$key" "$acct"
    return
  fi
  command -v wrangler >/dev/null 2>&1 || return 1
  bucket="$(kit_config_get_root proof.asset_bucket kit-proof-assets)"
  tokref="$(kit_config_get_root proof.asset_token_ref "")"
  if [ -n "$tokref" ] && command -v secret-cache-read >/dev/null 2>&1; then
    CLOUDFLARE_API_TOKEN="$(secret-cache-read --ttl 3600 CLOUDFLARE_API_TOKEN "$tokref")"
    export CLOUDFLARE_API_TOKEN
  fi
  CLOUDFLARE_ACCOUNT_ID="$acct" wrangler r2 object put "$bucket/$key" --file "$f" --remote >/dev/null
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

# _manifest_update <mfile> <idx> <status> <url> <sha> <bytes>
_manifest_update() {
  local m="$1" t="$1.tmp.$$"
  jq --argjson i "$2" --arg st "$3" --arg u "$4" --arg sha "$5" --argjson by "$6" \
    '.assets[$i].status = $st | .assets[$i].url = $u
     | .assets[$i].sha256 = $sha | .assets[$i].bytes = $by' \
    "$m" > "$t" && /bin/mv -f "$t" "$m"
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
  [ -n "$slug" ] || usage
  [ -n "$name" ] || name="${file##*/}"
  name="$(_slugify "${name%.*}")"
  [ -n "$name" ] || { echo "proof-asset: empty asset name" >&2; exit 64; }

  local tmpd; tmpd="$(mktemp -d)"; trap "rm -rf '$tmpd'" EXIT

  # GIFs pass through untouched; every other still goes through the converter.
  local kind ext cap work
  kind="$(_sniff_ext "$file")"
  [ "$kind" = bin ] && kind="$(printf '%s' "${file##*.}" | tr '[:upper:]' '[:lower:]')"
  if [ "$kind" = gif ]; then
    work="$file"; ext=gif; cap=2097152
  else
    work="$tmpd/conv"; _convert "$file" "$work"
    ext="$(_sniff_ext "$work")"
    [ "$ext" = bin ] && ext="$kind"
    cap=307200
  fi
  local bytes; bytes="$(wc -c < "$work" | tr -d ' ')"
  if [ "$bytes" -gt "$cap" ]; then
    echo "proof-asset: over cap: $bytes bytes (limit $cap)" >&2; exit 2
  fi

  local cache_dir="$root/.kit/proof-assets/$slug" fname="$name.$ext"
  mkdir -p "$cache_dir" "$root/docs/verification/$slug"
  /bin/cp -f "$work" "$cache_dir/$fname"
  local sha; sha="$(shasum -a 256 "$cache_dir/$fname" | awk '{print $1}')"

  local manifest="$root/docs/verification/$slug/assets.json" rand=""
  [ -f "$manifest" ] && rand="$(jq -r '.rand // empty' "$manifest" 2>/dev/null || true)"
  [ -n "$rand" ] || rand="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"

  local or owner="" repo="" base="" acct="" key="" url=""
  or="$(_owner_repo "$root" || true)"
  owner="${or%% *}"; repo="${or##* }"
  [ "$or" = "$owner" ] && repo=""
  [ -n "$owner" ] && base="$(kit_config_get_root "proof.base_url_$owner" "")"
  [ -n "$owner" ] && acct="$(kit_config_get_root "proof.account_$owner" "")"
  [ -n "$owner" ] && [ -n "$repo" ] && key="$owner/$repo/$slug/$rand/$fname"
  [ -n "$base" ] && [ -n "$key" ] && url="$base/$key"

  local mode status=pending why=""
  mode="$(kit_config_get proof.assets r2)"
  if [ "$mode" = local ]; then
    status=local
  elif [ -z "$key" ]; then
    why="no origin remote, cannot derive <owner>/<repo>"
  elif [ -z "$base" ]; then
    why="no proof.base_url_$owner in the operator kit.toml"
  elif [ -z "$acct" ]; then
    why="no proof.account_$owner in the operator kit.toml"
  elif _upload "$cache_dir/$fname" "$key" "$acct"; then
    status=uploaded
  else
    why="upload failed or offline"
  fi

  _manifest_put "$manifest" "$slug" "$rand" "$name" "$fname" "$status" "$url" "$sha" "$bytes"
  [ "$status" = pending ] \
    && printf 'queued: %s/%s (%s); run bin/proof-asset flush\n' "$slug" "$name" "$why" >&2
  if [ -n "$url" ] && [ "$status" != local ]; then
    printf '![%s](%s)\n' "$name" "$url"
  else
    printf '![%s](.kit/proof-assets/%s/%s)\n' "$name" "$slug" "$fname"
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

  local pending=0 failed=0 manifest mslug rand idxs i name file cache sha bytes key url
  for manifest in "$root"/docs/verification/*/assets.json; do
    [ -f "$manifest" ] || continue
    mslug="$(basename "$(dirname "$manifest")")"
    [ -n "$want" ] && [ "$mslug" != "$want" ] && continue
    rand="$(jq -r '.rand // empty' "$manifest" 2>/dev/null || true)"
    idxs="$(jq -r '.assets | to_entries[]? | select(.value.status == "pending") | .key' "$manifest" 2>/dev/null || true)"
    for i in $idxs; do
      pending=1
      name="$(jq -r ".assets[$i].name" "$manifest")"
      file="$(jq -r ".assets[$i].file" "$manifest")"
      cache="$root/.kit/proof-assets/$mslug/$file"
      if [ ! -f "$cache" ]; then
        echo "still pending: $mslug/$name (no cached file at .kit/proof-assets/$mslug/$file)" >&2
        failed=1; continue
      fi
      sha="$(shasum -a 256 "$cache" | awk '{print $1}')"
      bytes="$(wc -c < "$cache" | tr -d ' ')"
      if [ "$mode" = local ]; then
        _manifest_update "$manifest" "$i" local "" "$sha" "$bytes"
        continue
      fi
      key=""; url=""
      [ -n "$owner" ] && [ -n "$repo" ] && [ -n "$rand" ] && key="$owner/$repo/$mslug/$rand/$file"
      [ -n "$key" ] && [ -n "$base" ] && url="$base/$key"
      if [ -z "$key" ] || [ -z "$base" ] || [ -z "$acct" ]; then
        echo "still pending: $mslug/$name (no upload route: owner/base/account missing)" >&2
        failed=1; continue
      fi
      if _upload "$cache" "$key" "$acct"; then
        _manifest_update "$manifest" "$i" uploaded "$url" "$sha" "$bytes"
        echo "uploaded $mslug/$name"
      else
        echo "still pending: $mslug/$name (upload failed)" >&2
        failed=1
      fi
    done
  done
  [ "$pending" -eq 0 ] && exit 0
  [ "$failed" -gt 0 ] && exit 1
  exit 0
}

cmd="${1:-}"
case "$cmd" in
  put)   shift; cmd_put "$@" ;;
  flush) shift; [ $# -le 1 ] || usage; cmd_flush "${1:-}" ;;
  *) usage ;;
esac
