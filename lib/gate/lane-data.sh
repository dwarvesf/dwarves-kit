#!/usr/bin/env bash
# kit-verb: lane data | the one reader of lane data ([lane.<name>] and [lanes] in kit.toml) for the gate ledger and the classifier
# lane-data.sh -- the ONE reader of lane data ([lane.<name>] and [lanes] in kit.toml).
# Sourced by gate-ledger.sh (plan, required, check, start) and lane-classify.sh (default
# lane, extra hard paths). Prints nothing on load.
#
# Layers, highest first: the project .kit.toml (only when tracked and clean against HEAD, the
# same rule gate-policy.sh applies, so an agent cannot edit its own lane uncommitted), the
# operator overlay, then the kit root. The kit root is PINNED to the install this script lives
# in: KIT_CONFIG_ROOT and DWARVES_KIT in the environment cannot redirect it.
#
# Meaning of a lane block: a phase in `phases` and not in `light` is required; in both it is
# light; absent it is skipped. Array order is plan order. The winning layer supplies both
# arrays, so an override that sets `phases` and omits `light` has no light phases.
#
# Fail-closed rules: a value that is not a one-line ["a", "b"] array makes the lane unknown.
# A project or operator override naming a phase no kit lane knows is ignored for that lane
# (one stderr line), so a typo never drops a phase silently.
[ -n "${_LANE_DATA_SOURCED:-}" ] && return 0 2>/dev/null || true
_LANE_DATA_SOURCED=1

_LD_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
_LD_KIT_ROOT="$(cd "$_LD_DIR/../.." && pwd)"
# shellcheck source=lib/config/kit-config.sh
source "$_LD_DIR/../config/kit-config.sh"
LANE_NAMES="tiny normal full bug backfill"

_ld_kit_file() { printf '%s/kit.toml' "$_LD_KIT_ROOT"; }
_ld_operator_file() { kit_config_operator; }

# _ld_array <raw>: one element per line; exit 1 when raw is not a one-line array of names.
_ld_array() {
  local raw="$1" inner item rc=0
  case "$raw" in \[*\]) ;; *) return 1 ;; esac
  inner="${raw#\[}"; inner="${inner%\]}"
  [ -n "${inner//[[:space:]]/}" ] || return 0
  local IFS=','
  set -f   # a `*` in a value must not glob against the working directory
  # shellcheck disable=SC2086
  for item in $inner; do
    item="${item#"${item%%[![:space:]]*}"}"; item="${item%"${item##*[![:space:]]}"}"
    item="${item#\"}"; item="${item%\"}"
    printf '%s' "$item" | grep -Eq '^[a-z0-9][a-z0-9-]*$' || { rc=1; break; }
    printf '%s\n' "$item"
  done
  set +f
  return "$rc"
}

# lane_project_applies: 0 when the project .kit.toml is tracked and unmodified.
lane_project_applies() {
  local pf; pf="$(kit_config_project)"
  [ -f "$pf" ] || return 1
  kit_config_tracked_clean "$pf"
}

# The set of phase names any kit lane knows (kit root file only).
_ld_known_phases() {
  local l raw
  for l in $LANE_NAMES; do
    raw="$(_kit_toml_get "$(_ld_kit_file)" "lane.$l" phases)"
    _ld_array "$raw" 2>/dev/null
  done | sort -u
}

# _ld_kit_has_required <lane>: 0 when the kit root lane has at least one required phase.
_ld_kit_has_required() {
  local lane="$1" ph phases light
  phases="$(_ld_array "$(_kit_toml_get "$(_ld_kit_file)" "lane.$lane" phases)" 2>/dev/null)" || return 1
  light="$(_ld_array "$(_kit_toml_get "$(_ld_kit_file)" "lane.$lane" light)" 2>/dev/null)" || light=""
  while IFS= read -r ph; do
    [ -n "$ph" ] || continue
    printf '%s\n' "$light" | grep -qxF -- "$ph" || return 0
  done <<< "$phases"
  return 1
}

# lane_resolve <lane> [kit|nopro]: sets LANE_PHASES and LANE_LIGHT (newline lists).
# Exit 1 when the lane is unknown or its data is malformed. Mode `kit` reads the kit root ONLY
# (no operator overlay, no project); `nopro` skips just the project layer.
lane_resolve() {
  # KIT_LANE_PROJECT_AT=<rev>: read the project layer from the .kit.toml committed at <rev> (the merge
  # base at ship time), never the working tree, so a change under review cannot rewrite its own lanes.
  local _ld_at_file="" _ld_rc=0
  if [ -n "${KIT_LANE_PROJECT_AT:-}" ]; then
    _ld_at_file="$(mktemp)" || return 1
    kit_config_show_at "$(dirname "$(kit_config_project)")" "$KIT_LANE_PROJECT_AT" > "$_ld_at_file" 2>/dev/null || : > "$_ld_at_file"
  fi
  _ld_at_file="$_ld_at_file" _lane_resolve_layers "$@" || _ld_rc=$?
  [ -z "$_ld_at_file" ] || command rm -f "$_ld_at_file"
  return "$_ld_rc"
}
_lane_resolve_layers() {
  local lane="$1" mode="${2:-}" layer f raw lraw ph known applies
  LANE_PHASES=""; LANE_LIGHT=""
  # Only the five kit lanes exist here. A committed `[lane.mega]` block must not make `mega` a
  # lane whose gate check passes; drop-in lanes answer `plan` only, through lanes.d.
  case " $LANE_NAMES " in *" $lane "*) ;; *) return 1 ;; esac
  for layer in project operator kit; do
    case "$layer" in
      project)  [ -n "$mode" ] && continue; f="$(kit_config_project)"; [ -z "${_ld_at_file:-}" ] || f="$_ld_at_file" ;;
      operator) [ "$mode" = kit ] && continue; f="$(_ld_operator_file)" ;;
      kit)      f="$(_ld_kit_file)" ;;
    esac
    raw="$(_kit_toml_get "$f" "lane.$lane" phases)"
    [ -n "$raw" ] || continue
    if [ "$layer" = project ] && [ -z "${_ld_at_file:-}" ] && ! lane_project_applies; then
      echo "lane-data: [lane.$lane] in $f is ignored: the file is not committed and clean" >&2
      continue
    fi
    LANE_PHASES="$(_ld_array "$raw")" || { LANE_PHASES=""; return 1; }
    lraw="$(_kit_toml_get "$f" "lane.$lane" light)"
    if [ -n "$lraw" ]; then LANE_LIGHT="$(_ld_array "$lraw")" || { LANE_PHASES=""; LANE_LIGHT=""; return 1; }; fi
    if [ "$layer" != kit ]; then
      # An override may not empty a lane that carries required gates: `phases = []` would waive
      # every one of them.
      if [ -z "$LANE_PHASES" ] && _ld_kit_has_required "$lane"; then
        echo "lane-data: [lane.$lane] in $f sets no phases but the kit lane has required gates; override ignored, kit lane used" >&2
        LANE_PHASES=""; LANE_LIGHT=""
        continue
      fi
      known="$(_ld_known_phases)"
      while IFS= read -r ph; do
        [ -n "$ph" ] || continue
        if ! printf '%s\n' "$known" | grep -qxF -- "$ph"; then
          echo "lane-data: [lane.$lane] in $f names unknown phase '$ph'; override ignored, kit lane used" >&2
          LANE_PHASES=""; LANE_LIGHT=""
          continue 2
        fi
      done <<< "$LANE_PHASES"
    fi
    return 0
  done
  return 1
}

# lane_rows <lane> [kit|nopro]: "<phase>\t<measure-twice|run-lite>" in plan order; exit 1 = unknown lane.
lane_rows() {
  lane_resolve "$@" || return 1
  local ph
  while IFS= read -r ph; do
    [ -n "$ph" ] || continue
    if printf '%s\n' "$LANE_LIGHT" | grep -qxF -- "$ph"; then printf '%s\trun-lite\n' "$ph"
    else printf '%s\tmeasure-twice\n' "$ph"; fi
  done <<< "$LANE_PHASES"
}

# lane_dropped <lane>: phases the project override removed relative to the kit and operator lanes.
lane_dropped() {
  local lane="$1" kit eff ph
  lane_resolve "$lane" nopro 2>/dev/null || return 0
  kit="$LANE_PHASES"
  lane_resolve "$lane" 2>/dev/null || return 0
  eff="$LANE_PHASES"
  while IFS= read -r ph; do
    [ -n "$ph" ] || continue
    printf '%s\n' "$eff" | grep -qxF -- "$ph" || printf '%s\n' "$ph"
  done <<< "$kit"
}

# lane_default: the lane classify returns when no rule picks another.
lane_default() {
  local v pf; pf="$(kit_config_project)"
  v="$(_kit_toml_get "$pf" lanes default)"
  if [ -n "$v" ]; then
    if lane_project_applies; then :; else
      echo "lane-data: [lanes] default in $pf is ignored: the file is not committed and clean" >&2
      v=""
    fi
  fi
  [ -n "$v" ] || v="$(KIT_CONFIG_ROOT="$_LD_KIT_ROOT" kit_config_get_root lanes.default normal)"
  # tiny is not a default: it would waive the spec for every untagged task.
  if [ "$v" = tiny ]; then echo "lane-data: [lanes] default = tiny is not allowed; using normal" >&2; v=normal; fi
  case " $LANE_NAMES " in *" $v "*) printf '%s' "$v" ;; *) printf 'normal' ;; esac
}

# lane_extra_hard_paths: every ERE from [lanes] extra_hard_paths, one per line. The union of all
# layers, including both the working-tree and the HEAD copy of the project file, so a dirty edit
# that deletes an entry cannot drop it. KIT_FLOOR_CONFIG_AT=<rev> (the mega gate's PR-head mode) adds the
# copy committed at <rev>, so a stale checkout cannot drop an entry the base-branch tip carries. An
# invalid ERE is skipped with one stderr line.
lane_extra_hard_paths() {
  local pf d v r; pf="$(kit_config_project)"; d="$(dirname "$pf")"
  {
    _kit_toml_get "$pf" lanes extra_hard_paths
    if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local tmp; tmp="$(mktemp)"
      for r in HEAD ${KIT_FLOOR_CONFIG_AT:-}; do
        kit_config_show_at "$d" "$r" > "$tmp" && _kit_toml_get "$tmp" lanes extra_hard_paths
      done
      rm -f "$tmp"
    fi
    _kit_toml_get "$(_ld_operator_file)" lanes extra_hard_paths
    _kit_toml_get "$(_ld_kit_file)" lanes extra_hard_paths
  } | while IFS= read -r v; do
    [ -n "$v" ] || continue
    printf '' | grep -Eq -- "$v" 2>/dev/null; rc=$?
    if [ "$rc" -gt 1 ]; then echo "lane-data: extra_hard_paths entry '$v' is not a valid ERE; skipped" >&2; continue; fi
    printf '%s\n' "$v"
  done | sort -u
}

# lane_hard_path_exempt <root> <rev>: the hard-path exemption records from the .kit.toml committed at
# <rev>, else nothing. Only that copy counts: no working tree, no operator overlay, no kit root.
# Callers pass the merge base, so a PR cannot exempt its own push. The config is the array of
# tables [[gate.hard_path_exempt]] (keys paths, kinds, reason; kinds auth or migration only).
# Everything is validated before anything prints: any invalid entry refuses the WHOLE config (stdout
# empty, one stderr line per problem). Exit 0 always. Records, one per (entry, kind), TAB-separated:
#   <entry number> <kind> <ere> <globs joined by ", "> <reason>
# Not a TOML parser: it accepts exactly one-line arrays and double-quoted strings, and refuses the rest.
# A glob uses A-Z a-z 0-9 . _ - / @ + ~ * ?; `*` and `?` stay in one segment, `**` is a whole segment
# and crosses directories, and the match is anchored. An entry whose glob matches a canary is invalid:
# the built-in list below plus [gate] hard_path_canaries (literal paths) from the same <rev>.
_LD_EXEMPT_CANARIES='src/auth/login.ts
lib/session.ts
app/auth.py
.env
config/secrets/prod.txt
db/migrations/0001_init.sql
.github/workflows/ci.yml
Dockerfile'
lane_hard_path_exempt() {
  local root="$1" rev="$2" tmp can sha
  [ -n "$root" ] && [ -n "$rev" ] || return 0
  tmp="$(mktemp)" || return 0
  kit_config_show_at "$root" "$rev" > "$tmp"
  if ! grep -q 'hard_path_exempt\|hard_path_canaries' "$tmp"; then command rm -f "$tmp"; return 0; fi
  can="$(mktemp)" || { command rm -f "$tmp"; return 0; }
  printf '%s\n' "$_LD_EXEMPT_CANARIES" > "$can"
  sha="$(git -C "$root" rev-parse --short "$rev" 2>/dev/null || printf '%s' "$rev")"
  awk -v sha="$sha" '
    function trim(s) { sub(/^[[:space:]]+/, "", s); sub(/[[:space:]]+$/, "", s); return s }
    function sw(v, i) { while (substr(v, i, 1) ~ /[ \t]/) i++; return i }
    function cfgerr(m) { cerr[++ncerr] = m }
    function eerr(e, m) { if (err[e] == "") err[e] = m }
    # parse_arr <v>: fills AV[1..AN] from a one-line array of double-quoted strings; returns the problem or "".
    function parse_arr(v,   i, j, s, c) {
      AN = 0
      if (substr(v, 1, 1) != "[") return "value must be a one-line array of double-quoted strings"
      i = sw(v, 2)
      if (substr(v, i, 1) == "]") return "array is empty"
      while (1) {
        i = sw(v, i)
        if (substr(v, i, 1) != "\"") return "elements must be double-quoted strings on one line"
        j = index(substr(v, i + 1), "\"")
        if (j == 0) return "unterminated string"
        s = substr(v, i + 1, j - 1)
        if (index(s, "\\")) return "string holds a backslash"
        if (s ~ /[[:cntrl:]]/) return "string holds a control character"
        AV[++AN] = s; i = sw(v, i + j + 1)
        c = substr(v, i, 1)
        if (c == ",") { i = sw(v, i + 1); if (substr(v, i, 1) == "]") return "trailing comma"; continue }
        if (c == "]") { i++; break }
        return "expected a comma or ] after an element"
      }
      i = sw(v, i)
      if (substr(v, i) != "" && substr(v, i) !~ /^#/) return "text after the closing bracket"
      return ""
    }
    # parse_str <v>: AS = the content of a one-line double-quoted string; returns the problem or "".
    function parse_str(v,   j, s, i) {
      if (substr(v, 1, 1) != "\"") return "value must be a one-line double-quoted string"
      j = index(substr(v, 2), "\"")
      if (j == 0) return "unterminated string"
      s = substr(v, 2, j - 1)
      if (index(s, "\\")) return "string holds a backslash"
      if (s ~ /[[:cntrl:]]/) return "string holds a control character"
      i = sw(v, j + 2)
      if (substr(v, i) != "" && substr(v, i) !~ /^#/) return "text after the closing quote"
      AS = s; return ""
    }
    # glob_check <g>: the problem with a glob, or "".
    function glob_check(g,   ns, seg, i, s, allw) {
      if (g == "") return "glob is empty"
      if (g !~ "^[A-Za-z0-9._/@+~*?-]+$") return "glob \047" g "\047 uses a character outside A-Z a-z 0-9 . _ - / @ + ~ * ?"
      if (substr(g, 1, 1) == "/") return "glob \047" g "\047 starts with /"
      ns = split(g, seg, "/"); allw = 1
      for (i = 1; i <= ns; i++) {
        s = seg[i]
        if (s == "") return "glob \047" g "\047 has an empty segment"
        if (s == "." || s == "..") return "glob \047" g "\047 has a . or .. segment"
        if (index(s, "**") && s != "**") return "glob \047" g "\047 uses ** inside a segment"
        if (s != "*" && s != "**") allw = 0
      }
      if (allw) return "glob \047" g "\047 names no literal path (every segment is a wildcard)"
      return ""
    }
    # glob_ere <g>: the ERE body for a valid glob, translated in ONE left-to-right pass (a chained
    # rewrite lets a later rule edit an earlier rule output).
    function glob_ere(g,   ns, seg, i, j, s, c, out) {
      ns = split(g, seg, "/"); out = ""
      for (i = 1; i <= ns; i++) {
        s = seg[i]
        if (s == "**") { out = out (i < ns ? "(.*/)?" : ".+"); continue }
        for (j = 1; j <= length(s); j++) {
          c = substr(s, j, 1)
          out = out (c == "." ? "[.]" : (c == "+" ? "[+]" : (c == "*" ? "[^/]*" : (c == "?" ? "[^/]" : c))))
        }
        if (i < ns) out = out "/"
      }
      return out
    }
    NR == FNR { can[++nc] = $0; next }
    { line = $0; sub(/\r$/, "", line); if (FNR == 1 && substr(line, 1, 3) == "\357\273\277") line = substr(line, 4); t = trim(line) }
    t == "" || t ~ /^#/ { next }
    index(t, "\"\"\"") || index(t, "\047\047\047") { tq = 1 }
    t ~ /^\[/ {
      h = t; sub(/[[:space:]]*#.*$/, "", h); hn = h; gsub(/[[:space:]]/, "", hn)
      sec = "other"
      if (hn == "[[gate.hard_path_exempt]]") {
        hdr = 1
        if (h != "[[gate.hard_path_exempt]]") cfgerr("line " FNR ": the header must be exactly [[gate.hard_path_exempt]]")
        else { cur = ++ne; sec = "ent" }
      } else if (hn == "[gate.hard_path_exempt]") {
        hdr = 1; cfgerr("line " FNR ": use the array-of-tables header [[gate.hard_path_exempt]], not [gate.hard_path_exempt]")
      } else if (hn == "[gate]") sec = "gate"
      next
    }
    sec == "ent" {
      if (t !~ /^[A-Za-z_][A-Za-z0-9_-]*[[:space:]]*=/) { eerr(cur, "line " FNR ": expected a key = value line"); next }
      key = t; sub(/[[:space:]]*=.*$/, "", key); val = t; sub(/^[^=]*=[[:space:]]*/, "", val)
      if (key != "paths" && key != "kinds" && key != "reason") { eerr(cur, "line " FNR ": unknown key \047" key "\047"); next }
      if (seen[cur, key]++) { eerr(cur, "line " FNR ": duplicate key \047" key "\047"); next }
      if (key == "reason") { m = parse_str(val); if (m == "") R[cur] = AS }
      else {
        m = parse_arr(val)
        if (m == "") { if (key == "paths") { NP[cur] = AN; for (x = 1; x <= AN; x++) P[cur, x] = AV[x] } else { NK[cur] = AN; for (x = 1; x <= AN; x++) K[cur, x] = AV[x] } }
      }
      if (m != "") eerr(cur, "line " FNR ": " key ": " m)
      next
    }
    sec == "gate" && t ~ /^hard_path_canaries[[:space:]]*=/ {
      val = t; sub(/^[^=]*=[[:space:]]*/, "", val); m = parse_arr(val)
      if (m != "") { cfgerr("line " FNR ": hard_path_canaries: " m); next }
      for (x = 1; x <= AN; x++) {
        if (AV[x] !~ "^[A-Za-z0-9._@+~-][A-Za-z0-9._/@+~-]*$") cfgerr("line " FNR ": hard_path_canaries entry \047" AV[x] "\047 is not a literal repo path")
        else can[++nc] = AV[x]
      }
      next
    }
    index(t, "hard_path_canaries") { cfgerr("line " FNR ": hard_path_canaries is read only as a key under [gate]") }
    END {
      if (tq && hdr) cfgerr("the file holds a multi-line string; a table inside one cannot be told from an entry")
      if (ne > 32) cfgerr(ne " entries; the limit is 32")
      for (e = 1; e <= ne; e++) {
        m = err[e]
        if (m == "") for (x = 1; x <= 3 && m == ""; x++) { k = (x == 1 ? "paths" : x == 2 ? "kinds" : "reason"); if (!seen[e, k]) m = "missing key \047" k "\047" }
        for (x = 1; m == "" && x <= NP[e]; x++) {
          m = glob_check(P[e, x])
          if (m == "") {
            ere = "^(" glob_ere(P[e, x]) ")$"
            for (y = 1; y <= nc && m == ""; y++) if (can[y] ~ ere) m = "glob \047" P[e, x] "\047 matches the canary path \047" can[y] "\047"
          }
        }
        if (m == "" && trim(R[e]) == "") m = "reason must not be empty"
        if (m == "" && index(R[e], "|")) m = "reason must not hold |"
        for (x = 1; m == "" && x <= NK[e]; x++) {
          k = K[e, x]
          if (k == "secret" || k == "ci" || k == "infra" || k == "kit-config") m = "kind \047" k "\047 is never exemptable"
          else if (k != "auth" && k != "migration") m = "unknown kind \047" k "\047"
        }
        if (m != "") { nerr++; print "lane-data: [[gate.hard_path_exempt]] entry " e " at " sha ": " m "; no exemption applies" > "/dev/stderr" }
      }
      for (x = 1; x <= ncerr; x++) { nerr++; print "lane-data: [[gate.hard_path_exempt]] config at " sha ": " cerr[x] "; no exemption applies" > "/dev/stderr" }
      if (nerr) exit 0
      for (e = 1; e <= ne; e++) {
        globs = ""; ere = ""
        for (x = 1; x <= NP[e]; x++) { globs = globs (x > 1 ? ", " : "") P[e, x]; ere = ere (x > 1 ? "|" : "") "^(" glob_ere(P[e, x]) ")$" }
        delete done
        for (x = 1; x <= NK[e]; x++) { k = K[e, x]; if (done[k]++) continue; print e "\t" k "\t" ere "\t" globs "\t" R[e] }
      }
    }
  ' "$can" "$tmp"
  command rm -f "$tmp" "$can"
  return 0
}
