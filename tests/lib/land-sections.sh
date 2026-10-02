#!/usr/bin/env bash
# land-sections.sh -- the driver behind tests/test-wrap-land.sh. Sourced by that suite when
# LAND_SECTION is unset, never executed. The suite is a list of `sec_<id>() {` ... `} # end
# sec_<id>` functions, each opening with its `echo "=== title ==="` line. The driver:
#   - picks sections: LAND_ONLY=<ERE> matched against "<id> <title>" (default: all);
#   - skips a section whose key has a recorded pass (the cache), crediting its check count;
#   - runs the rest as child processes, `LAND_SECTION=sec_<id> bash <suite>`, at most
#     LAND_JOBS at once (default 4); each child sources the harness itself, so it owns its TMPD;
#   - prints each section's buffered output in suite order, then the suite's final line.
# Cache: tests/.cache/land/<key> holds `PASS <checks>`. The key hashes the section's source,
# the rest of the suite file, every file under lib/ bin/ tests/lib/ plus commands/wrap.md (a
# check reads it), the bash version and the git version. Only a full pass is recorded. Any read
# or write trouble means "run it". LAND_CACHE=0 turns it off; so does CI unless LAND_CACHE=1.
# bash 3.2 compatible: no associative arrays, no wait -n, no empty-array expansion.

land_sha() { # land_sha -- stdin to hex sha256
  if command -v sha256sum >/dev/null 2>&1; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}

land_tree_listing() { # land_tree_listing <root> -- "<sha> <path>" for every input the suite exercises
  local root="$1"
  ( cd "$root" || exit 1
    if command -v sha256sum >/dev/null 2>&1; then
      find lib bin tests/lib commands/wrap.md -type f ! -path '*/.venv/*' ! -path '*/__pycache__/*' ! -name '*.pyc' -print0 \
        | LC_ALL=C sort -z | xargs -0 sha256sum
    else
      find lib bin tests/lib commands/wrap.md -type f ! -path '*/.venv/*' ! -path '*/__pycache__/*' ! -name '*.pyc' -print0 \
        | LC_ALL=C sort -z | xargs -0 shasum -a 256
    fi )
}

land_section_text() { sed -n "/^$2() {\$/,/^} # end $2\$/p" "$1"; }
land_section_title() { sed -n "/^$2() {\$/{n;p;}" "$1" | sed 's/^echo "=== //; s/ ===".*$//'; }

land_drive() { # land_drive <suite file> [--list]
  set -u -o pipefail
  local suite="$1" root jobs only cache cdir ids id title sel nall nsel
  root="$(cd "$(dirname "$suite")/.." && pwd)"
  ids="$(grep -o '^sec_[a-z0-9_]*() {' "$suite" | sed 's/() {$//')"
  if [ "${2:-}" = "--list" ]; then
    for id in $ids; do printf '%s\t%s\n' "${id#sec_}" "$(land_section_title "$suite" "$id")"; done
    return 0
  fi

  jobs="${LAND_JOBS:-4}"; case "$jobs" in ''|*[!0-9]*|0) jobs=4 ;; esac
  only="${LAND_ONLY:-}"
  cache="${LAND_CACHE:-}"; if [ -z "$cache" ]; then if [ -n "${CI:-}" ]; then cache=0; else cache=1; fi; fi
  nall=0; nsel=0; sel=""
  for id in $ids; do
    nall=$((nall + 1))
    if [ -n "$only" ] && ! printf '%s %s\n' "${id#sec_}" "$(land_section_title "$suite" "$id")" | grep -Eq -- "$only"; then continue; fi
    sel="$sel $id"; nsel=$((nsel + 1))
  done
  if [ "$nsel" -eq 0 ]; then echo "test-wrap-land: LAND_ONLY='$only' matches no section (try --list)" >&2; return 64; fi

  # Globals, not locals: the traps below fire after this function's frame is gone.
  LAND_OUT="$(mktemp -d "${TMPDIR:-/tmp}/land-sections.XXXXXX")" || return 1
  local out="$LAND_OUT"
  trap 'rm -rf "$LAND_OUT"' EXIT

  # Cache setup. Any failure leaves cache=0, so every selected section runs.
  local libhash="" shared="" tools="" listing
  if [ "$cache" != 0 ]; then
    cdir="$root/tests/.cache/land"
    if mkdir -p "$cdir" 2>/dev/null && [ -r "$cdir" ] && [ -w "$cdir" ] \
       && listing="$(land_tree_listing "$root" 2>/dev/null)" && [ -n "$listing" ] \
       && libhash="$(printf '%s\n' "$listing" | land_sha)" && [ -n "$libhash" ]; then
      shared="$(awk '/^sec_[a-z0-9_]*\(\) \{$/{skip=1} !skip{print} /^} # end sec_/{skip=0}' "$suite")"
      tools="bash $BASH_VERSION; $(git --version 2>/dev/null)"
    else
      cache=0
    fi
  fi

  local key n tag rest
  : >"$out/run.list"
  for id in $sel; do
    if [ "$cache" != 0 ]; then
      key="$({ land_section_text "$suite" "$id"; printf '\n--shared--\n%s\n--tree--\n%s\n--tools--\n%s\n' "$shared" "$libhash" "$tools"; } | land_sha)"
      printf '%s' "$key" >"$out/$id.key"
      if [ -n "$key" ] && read -r tag n rest 2>/dev/null <"$cdir/$key" && [ "$tag" = PASS ]; then
        case "$n" in ''|*[!0-9]*) ;; *) if [ "$n" -gt 0 ]; then echo "$n" >"$out/$id.cached"; continue; fi ;; esac
      fi
    fi
    echo "$id" >>"$out/run.list"
  done

  if [ -s "$out/run.list" ]; then
    xargs -P "$jobs" -I{} "$BASH" -c 'LAND_SECTION="$1" "$2" "$3" >"$4/$1.out" 2>&1; echo $? >"$4/$1.rc"' _ {} "$BASH" "$suite" "$out" <"$out/run.list" &
    LAND_XPID=$!
    trap 'kill "$LAND_XPID" 2>/dev/null; pkill -TERM -P "$LAND_XPID" 2>/dev/null; exit 130' INT TERM HUP
    wait "$LAND_XPID"
  fi

  local P=0 F=0 T=0 nran=0 ncached=0 credited=0 res p f t rc red="\033[0;31m" nc="\033[0m"
  for id in $sel; do
    title="$(land_section_title "$suite" "$id")"
    if [ -f "$out/$id.cached" ]; then
      n="$(cat "$out/$id.cached")"
      echo "SKIP (cached pass) $title"
      P=$((P + n)); T=$((T + n)); ncached=$((ncached + 1)); credited=$((credited + n))
      continue
    fi
    nran=$((nran + 1))
    grep -v '^land-section-result: ' "$out/$id.out" 2>/dev/null
    res="$(grep '^land-section-result: ' "$out/$id.out" 2>/dev/null | tail -1)"
    rc="$(cat "$out/$id.rc" 2>/dev/null)"
    p=""; f=""; t=""
    # shellcheck disable=SC2086
    set -- ${res#land-section-result: }; p="${1:-}"; f="${2:-}"; t="${3:-}"
    case "$p$f$t" in ''|*[!0-9]*) p=""; f="" ;; esac
    if [ -z "$p" ] || [ -z "$f" ] || { [ "$rc" != 0 ] && [ "$f" = 0 ]; }; then
      echo -e "  ${red}FAIL${nc} section $id died without a result (rc=${rc:-none})"
      F=$((F + 1)); T=$((T + 1))
      continue
    fi
    P=$((P + p)); F=$((F + f)); T=$((T + t))
    if [ "$cache" != 0 ] && [ "$f" = 0 ] && [ "$rc" = 0 ] && [ "$p" -gt 0 ] && [ "$p" = "$t" ] && [ -s "$out/$id.key" ]; then
      key="$(cat "$out/$id.key")"
      { printf 'PASS %s\n' "$p" >"$cdir/.$key.$$" && mv -f "$cdir/.$key.$$" "$cdir/$key"; } 2>/dev/null || rm -f "$cdir/.$key.$$" 2>/dev/null
    fi
  done

  echo
  if [ "$nsel" -ne "$nall" ]; then echo "test-wrap-land: LAND_ONLY='$only' selected $nsel of $nall sections"; fi
  echo "test-wrap-land: $nsel sections, $nran ran, $ncached cached ($credited checks credited)"
  if [ "$F" -gt 0 ]; then echo "test-wrap-land: $P passed, $F FAILED of $T" >&2; return 1; fi
  echo "test-wrap-land: all $P passed"
}
