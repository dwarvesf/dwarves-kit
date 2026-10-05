#!/usr/bin/env bash
# kit-config.sh -- the single resolver for kit.toml config (config-layer).
#
# WHY: every runtime knob in the kit is an ad-hoc env var resolved in a different
# place. This is the ONE resolver (mirrors lib/telemetry/kit-log-dir.sh, "one place
# the default lives") that reads the layered config: the kit-root default kit.toml,
# overridden by an operator-owned kit.toml under the operator's XDG config dir, in turn
# overridden by a per-project .kit.toml (project WINS). Commands and feature libs
# call kit_config_get AT INVOCATION. Hot spine hooks NEVER source this -- that keeps
# the no-runtime-manifest-read lint green (it forbids HOOK reads, not command reads).
#
# Contract (safe under set -euo pipefail, no output on load):
#   kit_config_get <section.key> [default]   -> resolved value (project > operator > kit-root > default)
#   kit_config_root                           -> the kit-root kit.toml path in use
#   kit_config_operator                       -> the operator kit.toml path in use
#   kit_config_project                        -> the project .kit.toml path in use
#
# Precedence sources (each overridable for tests, a missing file is skipped silently):
#   project : $KIT_PROJECT_ROOT/.kit.toml   (default: $PWD/.kit.toml)
#   operator: $KIT_CONFIG_OPERATOR/kit.toml (default: ${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit/kit.toml)
#   kit-root: $KIT_CONFIG_ROOT/kit.toml     (default: ${DWARVES_KIT:-$HOME/.claude/dwarves-kit}/kit.toml)
#
# WHY the operator file exists: keys such as wrap.activity_log and precedent.registry name
# per-operator paths. The kit checkout is a shared, upgradable install, so it is the wrong
# home for one operator's paths. The operator file carries them across kit upgrades.
#
# Idempotent-source guard.
[ -n "${_KIT_CONFIG_SOURCED:-}" ] && return 0 2>/dev/null || true
_KIT_CONFIG_SOURCED=1

kit_config_root()     { printf '%s' "${KIT_CONFIG_ROOT:-${DWARVES_KIT:-$HOME/.claude/dwarves-kit}}/kit.toml"; }
kit_config_operator() { printf '%s' "${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit}/kit.toml"; }
kit_config_project()  { printf '%s' "${KIT_PROJECT_ROOT:-$PWD}/.kit.toml"; }

# _kit_toml_get_awk <file> <section> <key> -- the reference reader: one awk pass that stops at
# the first match. Line-oriented, no TOML lib (matches install.sh's grep/sed style). Handles:
# [section] headers, `#` full-line and inline comments, surrounding whitespace, and one layer
# of double-quotes. Values themselves must not contain a literal `#` (our schema never does).
# It is the semantic ground truth: the cache below must return exactly what this returns, and
# it still serves the inputs the cache declines (see _kit_toml_fast_ok).
_kit_toml_get_awk() {
  local file="$1" section="$2" key="$3"
  [ -f "$file" ] || return 0
  awk -v sec="$section" -v k="$key" '
    { line = $0 }
    line ~ /^[[:space:]]*#/ { next }                      # full-line comment
    line ~ /^[[:space:]]*\[/ {                            # section header
      h = line; sub(/#.*/, "", h); gsub(/[][[:space:]]/, "", h)
      insec = (h == sec); next
    }
    insec {
      sub(/#.*/, "", line)                                # strip inline comment
      if (line ~ ("^[[:space:]]*" k "[[:space:]]*=")) {
        sub(/^[^=]*=[[:space:]]*/, "", line)              # drop `key =`
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)     # trim
        gsub(/^"|"$/, "", line)                           # unquote
        print line; exit
      }
    }
  ' "$file"
}

# --- read-once cache (bash 3.2: no associative arrays) -------------------------------------
# WHY: a lookup used to spawn up to 3 awk plus 3 subshells. Now each distinct file CONTENT is
# parsed by ONE awk pass into "section<TAB>key<TAB>value" records, held in a variable, and a
# lookup is pure parameter expansion. Slots are parallel indexed arrays keyed by file path.
# The identity of a slot is the file's whole content, read with `$(<file)` (a builtin, no
# fork): size+mtime would need a stat fork per lookup, the cost this removes, and would miss a
# same-size edit inside one second or a reused mktemp path. Different path or different
# content re-parses, so a changed project root or a mid-process edit is always seen.
_KC_N=0 _KC_NEXT=0 _KC_PATH=() _KC_CONTENT=() _KC_RECS=()
_KC_MAX=16
_KC_V="" _KC_FOUND=0 _KC_RECS_CUR="" _KC_NEWC="" _KC_SLOT=-1

# One pass over a file: the same comment, header, trim and unquote statements as
# _kit_toml_get_awk, emitting a record per `key =` line. The section in force before the first
# header is none, so a headerless key matches no section (the reference's insec starts false).
_KC_AWK='
  { line = $0 }
  line ~ /^[[:space:]]*#/ { next }
  line ~ /^[[:space:]]*\[/ {
    h = line; sub(/#.*/, "", h); gsub(/[][[:space:]]/, "", h)
    cur = h; started = 1; next
  }
  started {
    sub(/#.*/, "", line)
    if (line !~ /=/) next
    kt = line; sub(/=.*/, "", kt); gsub(/^[[:space:]]+|[[:space:]]+$/, "", kt)
    if (kt == "" || kt ~ /[^A-Za-z0-9_-]/) next
    sub(/^[^=]*=[[:space:]]*/, "", line)
    gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
    gsub(/^"|"$/, "", line)
    printf "%s\t%s\t%s\n", cur, kt, line
  }
'

# _kit_toml_fast_ok <section> <key> -- 0 when the cache can answer exactly. The reference uses
# the key as a regex and passes both through `awk -v` (which expands backslash escapes), so a
# key outside [A-Za-z0-9_-], or a section holding whitespace or a backslash, goes to the
# reference reader instead. Our schema never produces one.
_kit_toml_fast_ok() {
  case "$2" in ''|*[!A-Za-z0-9_-]*) return 1 ;; esac
  case "$1" in *[[:space:]\\]*) return 1 ;; esac
  return 0
}

# _kit_toml_slot <file> -- compare <file> against its cached slot. 0 = hit (_KC_RECS_CUR set),
# 1 = parse needed (_KC_NEWC holds the content, _KC_SLOT the slot to refill or -1 for a new
# path), 2 = missing or unreadable. Runs in the C locale: bash 3.2 string work is about twice as
# slow under UTF-8 and every value here is compared byte for byte anyway.
_kit_toml_slot() {
  local LC_ALL=C file="$1" i=0
  _KC_RECS_CUR=""; _KC_SLOT=-1
  [ -f "$file" ] || return 2
  { _KC_NEWC="$(<"$file")"; } 2>/dev/null || return 2
  while [ "$i" -lt "$_KC_N" ]; do
    if [ "${_KC_PATH[$i]}" = "$file" ]; then
      _KC_SLOT="$i"
      [[ "${_KC_CONTENT[$i]}" == "$_KC_NEWC" ]] && { _KC_RECS_CUR="${_KC_RECS[$i]}"; return 0; }
      return 1
    fi
    i=$((i + 1))
  done
  return 1
}

# _kit_toml_load <file> -- make the record cache for <file> current; sets _KC_RECS_CUR. Returns
# 1 when <file> is missing or unreadable (the caller then uses the reference reader).
_kit_toml_load() {
  local file="$1" recs rc
  _kit_toml_slot "$file" && rc=0 || rc=$?
  [ "$rc" = 0 ] && return 0
  [ "$rc" = 1 ] || return 1
  recs="$(awk "$_KC_AWK" "$file" 2>/dev/null)" || return 1
  if [ "$_KC_SLOT" -lt 0 ]; then                          # new path: take a free slot, else recycle
    if [ "$_KC_N" -lt "$_KC_MAX" ]; then _KC_SLOT="$_KC_N"; _KC_N=$((_KC_N + 1))
    else _KC_SLOT="$_KC_NEXT"; _KC_NEXT=$(((_KC_NEXT + 1) % _KC_MAX)); fi
  fi
  _KC_PATH[$_KC_SLOT]="$file"; _KC_CONTENT[$_KC_SLOT]="$_KC_NEWC"; _KC_RECS[$_KC_SLOT]=$'\n'"$recs"
  _KC_RECS_CUR="${_KC_RECS[$_KC_SLOT]}"
}

# _kit_toml_find <section> <key> -- search the current record set (_KC_RECS_CUR). Sets _KC_V and
# _KC_FOUND (1 when the key line exists, even with an empty value). The first record for a
# (section,key) wins, like the reference's `exit` on first match.
_kit_toml_find() {
  local LC_ALL=C pat before rest
  _KC_V=""; _KC_FOUND=0
  pat=$'\n'"$1"$'\t'"$2"$'\t'
  case "$_KC_RECS_CUR" in *"$pat"*) ;; *) return 0 ;; esac
  before="${_KC_RECS_CUR%%"$pat"*}"
  rest="${_KC_RECS_CUR:$((${#before} + ${#pat}))}"
  _KC_V="${rest%%$'\n'*}"; _KC_FOUND=1
}

# _kit_toml_lookup <file> <section> <key> -- sets _KC_V (the value, "" when absent). No
# subshell, no output. An input the cache declines is read by the reference reader.
_kit_toml_lookup() {
  _KC_V=""; _KC_FOUND=0
  [ -f "$1" ] || return 0
  if _kit_toml_fast_ok "$2" "$3" && _kit_toml_load "$1"; then
    _kit_toml_find "$2" "$3"
  else
    _KC_V="$(_kit_toml_get_awk "$1" "$2" "$3")"
  fi
  return 0
}

# _kit_toml_get <file> <section> <key> -- print the raw value of [section].key, empty if absent.
# Same stdout as the reference reader (a found key prints its value and a newline, an absent
# key prints nothing), served from the cache. Direct callers (lane-data.sh, gate-policy.sh,
# config.sh) get the read-once behaviour too.
_kit_toml_get() {
  if _kit_toml_fast_ok "$2" "$3" && _kit_toml_load "$1"; then
    _kit_toml_find "$2" "$3"
    [ "$_KC_FOUND" = 1 ] && printf '%s\n' "$_KC_V"
    return 0
  fi
  _kit_toml_get_awk "$@"
}

# kit_config_get <section.key> [default] -- project override, else operator, else kit-root,
# else default. The dotted key splits at the LAST dot: `lane.normal.phases` reads section
# `lane.normal`, key `phases`. A missing file at any layer is skipped silently. The layer paths
# are the same expansions as kit_config_project/operator/root, inlined so a lookup forks nothing.
kit_config_get() {
  local dotkey="$1" def="${2:-}" section key
  section="${dotkey%.*}"; key="${dotkey##*.}"
  _kit_toml_lookup "${KIT_PROJECT_ROOT:-$PWD}/.kit.toml" "$section" "$key"
  [ -n "$_KC_V" ] && { printf '%s' "$_KC_V"; return 0; }
  _kit_toml_lookup "${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-${HOME:-}/.config}/dwarves-kit}/kit.toml" "$section" "$key"
  [ -n "$_KC_V" ] && { printf '%s' "$_KC_V"; return 0; }
  _kit_toml_lookup "${KIT_CONFIG_ROOT:-${DWARVES_KIT:-${HOME:-}/.claude/dwarves-kit}}/kit.toml" "$section" "$key"
  [ -n "$_KC_V" ] && { printf '%s' "$_KC_V"; return 0; }
  printf '%s' "$def"
}

# kit_config_get_root <section.key> [default] -- operator, else kit-root, else default. The
# project overlay is SKIPPED. For security-bearing keys a committed project .kit.toml must
# NOT be able to set: a project toml rides inside an untrusted PR, so a key that selects a
# runner host, a secret ref, or a dispatch target must resolve from an operator-owned file
# alone. Same read-model the kit already applies to enabled_agent_clis. The operator file
# carries the same trust as the kit root: it sits on the operator's own machine and never
# rides inside a pull request.
kit_config_get_root() {
  local dotkey="$1" def="${2:-}" section key
  section="${dotkey%.*}"; key="${dotkey##*.}"
  _kit_toml_lookup "${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-${HOME:-}/.config}/dwarves-kit}/kit.toml" "$section" "$key"
  [ -n "$_KC_V" ] && { printf '%s' "$_KC_V"; return 0; }
  _kit_toml_lookup "${KIT_CONFIG_ROOT:-${DWARVES_KIT:-${HOME:-}/.claude/dwarves-kit}}/kit.toml" "$section" "$key"
  [ -n "$_KC_V" ] && { printf '%s' "$_KC_V"; return 0; }
  printf '%s' "$def"
}

# Prime the cache at source time. Callers read keys as `v="$(kit_config_get ...)"`, and a
# subshell's cache dies with it, so only a cache filled in the SOURCING shell is inherited by
# those subshells. A layer that is absent costs nothing; a changed path or content later just
# re-parses. Never fatal, never prints.
_kit_toml_load "${KIT_PROJECT_ROOT:-$PWD}/.kit.toml" || true
_kit_toml_load "${KIT_CONFIG_OPERATOR:-${XDG_CONFIG_HOME:-${HOME:-}/.config}/dwarves-kit}/kit.toml" || true
_kit_toml_load "${KIT_CONFIG_ROOT:-${DWARVES_KIT:-${HOME:-}/.claude/dwarves-kit}}/kit.toml" || true

# kit_config_tracked_clean <file> -- exit 0 when <file> is tracked in its git repo and unmodified
# against HEAD. The rule for a project file that may weaken a gate: an uncommitted edit leaves no
# trace in the PR, so it does not count. gate-policy.sh and lane-data.sh both use it.
kit_config_tracked_clean() {
  local f="$1" d b; d="$(dirname "$f")"; b="$(basename "$f")"
  git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    && git -C "$d" ls-files --error-unmatch "$b" >/dev/null 2>&1 \
    && git -C "$d" diff --quiet HEAD -- "$b" 2>/dev/null
}

# kit_config_show_at <repo-root> <rev> -- the committed .kit.toml at <rev> on stdout; empty when the
# file is absent there. A copy at a base is committed by definition.
kit_config_show_at() { git -C "$1" show "$2:.kit.toml" 2>/dev/null; }

# --- self-test: `bash lib/config/kit-config.sh selftest` (ponytail: one runnable check) ---
# EXECUTED-directly guard: a sourced file inherits the CALLER's "$@". Without this, any
# verb-taking CLI that sources this lib and is invoked with `selftest` (e.g. `queue.sh
# selftest`) silently ran this suite AND inherited its `set -euo pipefail` + EXIT trap, into
# a launcher that deliberately runs without -e. Reproduced and fixed (review finding).
if [ "${BASH_SOURCE[0]}" = "$0" ] && [ "${1:-}" = "selftest" ]; then
  set -euo pipefail
  d="$(mktemp -d)"; trap 'rm -rf "$d"' EXIT
  mkdir -p "$d/root" "$d/proj" "$d/op"
  cat > "$d/root/kit.toml" <<'TOML'
[ledger]
location = "shared"   # inline comment must be stripped
[mega]
wave_cap = 2
# over_test = false   # full-comment line must be ignored
TOML
  cat > "$d/proj/.kit.toml" <<'TOML'
[ledger]
location = "isolated"
[gauntlet]
runner_host = "evil-host"
[knowledge]
root = "/tmp/proj"
TOML
  cat > "$d/op/kit.toml" <<'TOML'
[ledger]
location = "operator"
[mega]
wave_cap = 9
[gauntlet]
runner_host = "operator-host"
[knowledge]
root = "/tmp/op"
TOML
  # The base cases pin the operator layer at a path that does not exist, so the operator's
  # REAL ~/.config/dwarves-kit/kit.toml can never leak into this suite on a live machine.
  export KIT_CONFIG_ROOT="$d/root" KIT_PROJECT_ROOT="$d/proj" KIT_CONFIG_OPERATOR="$d/none"
  fail=0
  chk() { [ "$2" = "$3" ] && echo "ok   $1" || { echo "FAIL $1: got [$2] want [$3]"; fail=1; }; }
  chk "project overrides kit-root"      "$(kit_config_get ledger.location)"    "isolated"
  chk "kit-root default when no proj"   "$(kit_config_get mega.wave_cap)"      "2"
  chk "inline comment stripped"         "$(KIT_PROJECT_ROOT=/nonexistent kit_config_get ledger.location)" "shared"
  chk "commented key -> caller default" "$(kit_config_get mega.over_test off)" "off"
  chk "missing key -> caller default"   "$(kit_config_get nope.nope fallback)" "fallback"
  chk "missing section -> empty"        "$(kit_config_get ghost.key)"          ""
  # root-only read: a malicious project .kit.toml MUST NOT win a security-bearing key.
  chk "root-only ignores project override" "$(kit_config_get_root gauntlet.runner_host local)" "local"
  chk "root-only reads kit-root value"     "$(kit_config_get_root mega.wave_cap)"               "2"
  chk "root-only falls to caller default"  "$(kit_config_get_root gauntlet.nope fallback)"      "fallback"
  # negative control: the LEGACY accessor still lets the project override through (proves
  # the two accessors differ, and that the project toml IS being read).
  chk "legacy accessor still overridable"  "$(kit_config_get gauntlet.runner_host local)"       "evil-host"
  # operator overlay: as trusted as the kit root (it sits on the operator's machine, never in
  # a PR), so it wins the root-only read; the project toml still wins the plain read.
  chk "operator wins kit-root on _root" \
    "$(KIT_CONFIG_OPERATOR="$d/op" kit_config_get_root mega.wave_cap)"                          "9"
  chk "operator wins kit-root on get" \
    "$(KIT_CONFIG_OPERATOR="$d/op" KIT_PROJECT_ROOT=/nonexistent kit_config_get ledger.location)" "operator"
  chk "project still wins operator on get" \
    "$(KIT_CONFIG_OPERATOR="$d/op" kit_config_get ledger.location)"                             "isolated"
  chk "project never reaches _root past operator" \
    "$(KIT_CONFIG_OPERATOR="$d/op" kit_config_get_root ledger.location)"                        "operator"
  printf '[lane.normal]\nphases = ["spec", "build"]\n' >> "$d/root/kit.toml"
  chk "last-dot split: lane.normal.phases" \
    "$(KIT_PROJECT_ROOT=/nonexistent kit_config_get lane.normal.phases)"                        '["spec", "build"]'
  chk "last-dot split on _root" \
    "$(kit_config_get_root lane.normal.phases)"                                                 '["spec", "build"]'
  chk "missing operator file falls through" \
    "$(KIT_CONFIG_OPERATOR="$d/none" kit_config_get_root mega.wave_cap)"                        "2"
  chk "KIT_CONFIG_OPERATOR redirects the file" \
    "$(KIT_CONFIG_OPERATOR="$d/none" kit_config_get_root gauntlet.runner_host local)"           "local"
  # [knowledge] root is a root-only key like gauntlet.runner_host --
  # a project .kit.toml MUST NOT be able to redirect where knowledge notes land.
  chk "root-only knowledge.root: operator wins over kit-root, project ignored" \
    "$(KIT_CONFIG_OPERATOR="$d/op" kit_config_get_root knowledge.root)"                         "/tmp/op"
  chk "root-only knowledge.root: empty with no operator/kit-root value, even though project sets it" \
    "$(kit_config_get_root knowledge.root)"                                                     ""
  [ "$fail" = 0 ] && echo "PASS kit-config selftest" || { echo "SELFTEST FAILED"; exit 1; }
fi
