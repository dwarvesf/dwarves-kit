#!/usr/bin/env bash
# adapters.sh -- the bash reader of the adapter manifests, sourced by board.sh and board-sweep.
#
# The twin of lib/sync/adapters.py: both read lib/adapters/<name>/adapter.tsv (or $KIT_ADAPTERS_DIR) with
# the same grammar and fail with the same `adapters: <file>:<line>: <what is wrong>` line. It is pure bash
# and awk on purpose: the dispatch suite stubs python3, and `board next` must stay cheap.
#
#   adapters_dir             the one directory scanned
#   adapters_rows <kind>     <adapter dir><TAB><fields...> for every row of that kind, adapters in name order
#   adapters_verb <verb>     <script path><TAB><args...>, or return 1 (always 1 for a core verb, at once)
#   adapters_const <n> <d>   the value of a `const` row (first adapter that declares it), else <d>
#
# Sourcing it prints nothing and runs nothing. bash 3.2 clean: no mapfile, no associative arrays.
if [ -n "${_KIT_ADAPTERS_SH:-}" ]; then return 0; fi
_KIT_ADAPTERS_SH=1

# The verbs core owns: the board.sh main() labels that are not adapter verbs, and the backlog.sh verbs.
CORE_VERBS="all queue sync publish sweep init capture promote normalize run work health brief help board next get row set dedupe dedupe-all lint add states machine"
# The flags core owns, so a manifest cannot shadow one (the engine's argparse, then board-sweep's case list).
ADAPTERS_ENGINE_FLAGS="apps surfaces sources backlog archive-file state-root dry-run filter scope-exit-cap allow-scope-exit allow-flips allow-archived-closes help"
ADAPTERS_SWEEP_FLAGS="registry name board-cmd extra-board repo-arg sync-token-repo preflight poster on-clean cluster-map crit-prefix field-cap health health-force health-every-days health-stale-days health-kanban health-line health-quiet health-hub health-board health-faults-only health-triage-open health-triage-days health-state-file state-file repo-root dry-run help"

# The real directory of this file, following a symlinked file and a symlinked directory (this host links
# lib into the kit checkout), so the default adapter directory never depends on cwd or on a config value.
_adapters_self_dir() {
  local src="${BASH_SOURCE[0]}" dir link
  while [ -L "$src" ]; do
    dir="$(cd "$(dirname "$src")" && pwd -P)"; link="$(readlink "$src")"
    case "$link" in /*) src="$link" ;; *) src="$dir/$link" ;; esac
  done
  (cd "$(dirname "$src")" && pwd -P)
}

adapters_dir() {
  if [ "${KIT_ADAPTERS_DIR+set}" = set ]; then
    case "$KIT_ADAPTERS_DIR" in
      /*) printf '%s\n' "$KIT_ADAPTERS_DIR"; return 0 ;;
      *) echo "adapters: KIT_ADAPTERS_DIR must be an absolute path" >&2; return 1 ;;
    esac
  fi
  local self; self="$(_adapters_self_dir)"
  printf '%s/adapters\n' "${self%/*}"
}

# The grammar, once. Prints `ROW<TAB><kind><TAB><adapter dir><TAB><fields...>` for each valid row and, on the
# first bad one, `ERR<TAB><message>`. Keep it in step with adapters.py (the same checks, in the same order).
_adapters_awk_program() {
  cat <<'AWK'
function fail_at(file, line, msg) {
  printf "ERR\tadapters: %s:%d: %s\n", file, line, msg
  failed = 1
  exit 1
}
function shq(s) { gsub(/'/, "'\\''", s); return "'" s "'" }
function in_list(item, list,   n, a, i) {
  n = split(list, a, " ")
  for (i = 1; i <= n; i++) if (a[i] == item) return 1
  return 0
}
function claim(ns, key) {
  if ((ns SUBSEP key) in seen) fail_at(cur_file, FNR, "duplicate " ns " '" key "' (also in " seen[ns SUBSEP key] ")")
  seen[ns SUBSEP key] = cur_file ":" FNR
}
function env_ok(env,   i, n, p) {
  if (env !~ /^[A-Z][A-Z0-9_]*$/) fail_at(cur_file, FNR, "bad ENV name '" env "'")
  if (in_list(env, "PATH HOME IFS ENV BASH_ENV SHELLOPTS BASHOPTS PS4 PROMPT_COMMAND CDPATH"))
    fail_at(cur_file, FNR, "reserved ENV name '" env "'")
  n = split("LD_ DYLD_ PYTHON KIT_ SWEEP_ BOARD_ GIT_ SSH_ OP_ NODE_", p, " ")
  for (i = 1; i <= n; i++)
    if (index(env, p[i]) == 1) fail_at(cur_file, FNR, "reserved ENV prefix '" p[i] "' in '" env "'")
}
function script_ok(script,   n, parts, i) {
  n = split(script, parts, "/")
  bad = (substr(script, 1, 1) == "/")
  for (i = 1; i <= n; i++) if (parts[i] == "..") bad = 1
  if (bad) fail_at(cur_file, FNR, "bad script path '" script "' (relative, inside the adapter directory, no ..)")
  if (system("test -L " shq(cur_dir "/" script)) == 0) fail_at(cur_file, FNR, "script '" script "' is a symlink")
}
function start_file(   n, parts) {
  cur_file = FILENAME
  cur_dir = FILENAME
  sub(/\/adapter\.tsv$/, "", cur_dir)
  split("", optkey); split("", optscope); split("", optline)
  nopt = 0; has_secret = 0; entry_row = 0
}
function end_file(   i) {
  if (has_secret)
    for (i = 1; i <= nopt; i++)
      if (optscope[i] == "-" && optkey[i] ~ /_(url|host|endpoint|target)$/)
        fail_at(cur_file, optline[i], "opt key '" optkey[i] "' has scope - and sits beside a secret row (a project file could aim the secret at a host); use scope root")
  if (entry_row) {
    if (system("test -L " shq(cur_dir "/adapter.py")) == 0) fail_at(cur_file, entry_row, "adapter.py is a symlink")
    if (system("test -f " shq(cur_dir "/adapter.py")) != 0) fail_at(cur_file, entry_row, "adapter.py is missing")
  }
}
BEGIN {
  FS = "\t"
  lo["app"] = 2; hi["app"] = 2
  lo["opt"] = 4; hi["opt"] = -1
  lo["secret"] = 2; hi["secret"] = 2
  lo["verb"] = 2; hi["verb"] = -1
  lo["sweep-opt"] = 3; hi["sweep-opt"] = -1
  lo["leg"] = 2; hi["leg"] = 2
  lo["const"] = 2; hi["const"] = -1
  lo["hook"] = 1; hi["hook"] = 1
  core_dests = core_engine
  gsub(/-/, "_", core_dests)
}
FNR == 1 {
  if (cur_file != "") end_file()
  start_file()
}
{
  line = $0
  sub(/\r$/, "", line)
  if (line ~ /^[ \t]*$/ || substr(line, 1, 1) == "#") next
  n = split(line, f, "\t")
  kind = f[1]
  if (!(kind in lo)) next
  nf = n - 1
  if (nf < lo[kind] || (hi[kind] >= 0 && nf > hi[kind]))
    fail_at(cur_file, FNR, kind " needs " (lo[kind] == hi[kind] ? "" : "at least ") lo[kind] " fields")
  for (i = 2; i <= n; i++) if (f[i] == "") fail_at(cur_file, FNR, "empty field")
  if (kind == "app") {
    if (f[2] !~ /^[a-z][a-z0-9-]*$/) fail_at(cur_file, FNR, "bad app name '" f[2] "'")
    if (!in_list(f[3], "two-way create-only pull-only"))
      fail_at(cur_file, FNR, "bad mode '" f[3] "' (want two-way, create-only or pull-only)")
    claim("app", f[2])
  } else if (kind == "opt") {
    if (f[2] !~ /^[a-z][a-z0-9-]*$/) fail_at(cur_file, FNR, "bad flag '" f[2] "'")
    if (f[3] !~ /^[a-z][a-z0-9_]*$/) fail_at(cur_file, FNR, "bad key '" f[3] "'")
    if (f[4] != "-" && f[4] != "root") fail_at(cur_file, FNR, "bad scope '" f[4] "' (want - or root)")
    if (in_list(f[2], core_engine)) fail_at(cur_file, FNR, "flag '" f[2] "' is a core engine flag")
    if (in_list(f[3], core_dests)) fail_at(cur_file, FNR, "key '" f[3] "' is a core engine dest")
    claim("flag", f[2])
    claim("key", f[3])
    nopt++; optkey[nopt] = f[3]; optscope[nopt] = f[4]; optline[nopt] = FNR
  } else if (kind == "secret") {
    env_ok(f[2])
    if (f[3] !~ /^[a-z][a-z0-9_]*$/) fail_at(cur_file, FNR, "bad key '" f[3] "'")
    claim("ENV", f[2])
    claim("key", f[3])
    has_secret = 1
  } else if (kind == "verb") {
    if (f[2] !~ /^[a-z][a-z0-9-]*$/) fail_at(cur_file, FNR, "bad verb '" f[2] "'")
    script_ok(f[3])
    if (in_list(f[2], core_verbs)) fail_at(cur_file, FNR, "verb '" f[2] "' is a core verb")
    claim("verb", f[2])
  } else if (kind == "sweep-opt") {
    if (f[2] !~ /^[a-z][a-z0-9-]*$/) fail_at(cur_file, FNR, "bad flag '" f[2] "'")
    env_ok(f[3])
    if (in_list(f[2], core_sweep)) fail_at(cur_file, FNR, "flag '" f[2] "' is a core sweep flag")
    claim("sweep flag", f[2])
    claim("ENV", f[3])
  } else if (kind == "leg") {
    if (!in_list(f[2], "after-sync last")) fail_at(cur_file, FNR, "bad phase '" f[2] "' (want after-sync or last)")
    script_ok(f[3])
  } else if (kind == "const") {
    if (f[2] !~ /^[a-z][a-z0-9-]*$/) fail_at(cur_file, FNR, "bad const name '" f[2] "'")
    claim("const", f[2])
  } else if (kind == "hook") {
    if (!in_list(f[2], "guard body_expander brief_decisions"))
      fail_at(cur_file, FNR, "bad hook name '" f[2] "' (want guard, body_expander or brief_decisions)")
    if (f[2] == "body_expander") claim("hook", f[2])
  }
  if ((kind == "app" || kind == "hook") && !entry_row) entry_row = FNR
  printf "ROW\t%s\t%s", kind, cur_dir
  for (i = 2; i <= n; i++) printf "\t%s", f[i]
  printf "\n"
}
END {
  if (failed) exit 1
  if (cur_file != "") end_file()
}
AWK
}

# _adapters_scan: print the canonical rows, or the error and return 1. The grammar is checked for every
# manifest, because one bad manifest stops every run that loads the registry (by design).
_adapters_scan() {
  local dir name f out bad="" prog
  local files=()
  dir="$(adapters_dir)" || return 1
  [ -e "$dir" ] || return 0
  if [ ! -d "$dir" ] || [ ! -r "$dir" ] || [ ! -x "$dir" ]; then
    echo "adapters: cannot read $dir" >&2; return 1
  fi
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    case "$name" in .*|_*) continue ;; esac
    [ -d "$dir/$name" ] && [ -f "$dir/$name/adapter.tsv" ] || continue
    case "$name" in
      [a-z]*) case "$name" in *[!a-z0-9-]*) bad="$name" ;; esac ;;
      *) bad="$name" ;;
    esac
    [ -z "$bad" ] || break
    files+=("$dir/$name/adapter.tsv")
  done < <(LC_ALL=C ls -1 "$dir" 2>/dev/null)
  if [ ${#files[@]} -gt 0 ]; then
    prog="$(_adapters_awk_program)"
    out="$(awk -v core_verbs="$CORE_VERBS" -v core_engine="$ADAPTERS_ENGINE_FLAGS" -v core_sweep="$ADAPTERS_SWEEP_FLAGS" \
      "$prog" "${files[@]}")" || true
    f="$(printf '%s\n' "$out" | awk -F'\t' '$1 == "ERR" { print $2; exit }')"
    if [ -n "$f" ]; then printf '%s\n' "$f" >&2; return 1; fi
    [ -z "$out" ] || printf '%s\n' "$out"
  fi
  if [ -n "$bad" ]; then
    echo "adapters: $dir/$bad/adapter.tsv:1: bad adapter directory name '$bad'" >&2; return 1
  fi
  return 0
}

adapters_rows() {
  local out
  out="$(_adapters_scan)" || return 1
  [ -z "$out" ] || printf '%s\n' "$out" | awk -F'\t' -v k="$1" '$1 == "ROW" && $2 == k { sub(/^ROW\t[^\t]*\t/, ""); print }'
  return 0
}

adapters_verb() {
  local v out
  for v in $CORE_VERBS; do [ "$v" = "$1" ] && return 1; done
  out="$(_adapters_scan)" || return 1
  [ -n "$out" ] || return 1
  printf '%s\n' "$out" | awk -F'\t' -v v="$1" '
    $1 == "ROW" && $2 == "verb" && $4 == v {
      printf "%s/%s", $3, $5
      for (i = 6; i <= NF; i++) printf "\t%s", $i
      printf "\n"; found = 1; exit
    }
    END { exit found ? 0 : 1 }'
}

adapters_const() {
  local out val=""
  out="$(_adapters_scan)" || return 1
  if [ -n "$out" ]; then
    val="$(printf '%s\n' "$out" | awk -F'\t' -v n="$1" '
      $1 == "ROW" && $2 == "const" && $4 == n {
        s = $5
        for (i = 6; i <= NF; i++) s = s " " $i
        print s; exit
      }')"
  fi
  if [ -n "$val" ]; then printf '%s\n' "$val"; else printf '%s\n' "${2:-}"; fi
}
