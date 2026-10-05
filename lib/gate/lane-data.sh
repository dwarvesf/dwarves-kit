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
# that deletes an entry cannot drop it. An invalid ERE is skipped with one stderr line.
lane_extra_hard_paths() {
  local pf d v; pf="$(kit_config_project)"; d="$(dirname "$pf")"
  {
    _kit_toml_get "$pf" lanes extra_hard_paths
    if git -C "$d" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      local tmp; tmp="$(mktemp)"
      kit_config_show_at "$d" HEAD > "$tmp" && _kit_toml_get "$tmp" lanes extra_hard_paths
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
