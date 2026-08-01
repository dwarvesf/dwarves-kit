#!/usr/bin/env bash
# feature-registry.sh -- deterministic feature-inventory generator (SPEC-219).
#
# Scans the four live feature kinds (commands/*.md, agents/*.md, skills/*/SKILL.md,
# hooks/*.sh) and emits docs/FEATURES.md as a GENERATED projection: one table per
# kind, one row per feature, carrying trigger class, description, spec refs, and
# test refs. Pure bash + grep/sed/awk/jq (all already required by tests/).
#
# Deterministic by construction: LC_ALL=C, sorted globs, no timestamps in the
# output -- tests/test-meta.sh pins freshness by regenerating to a temp file and
# diffing against the committed docs/FEATURES.md, so any nondeterministic byte
# would be a permanent RED.
#
# Trigger classes (derivation rules, no judgment):
#   [H]   command/skill with frontmatter `disable-model-invocation: true`
#   [H/I] any other command
#   [I]   any other skill
#   [E]   hook; event(s) looked up in hooks/hooks.json (statusline.sh rides the
#         settings.json statusLine key); wired nowhere -> event `-`
#   [D]   agent; dispatched-by derived by token-grepping commands/*.md and
#         skills/*/SKILL.md (skill dispatchers marked `(skill)`)
#
# `generate` also syncs the hand-maintained count strings in README.md and
# docs/architecture.md (agents/commands/skills/hooks totals) so nobody has to
# recompute and hand-edit them when a feature is added or removed; the
# corresponding tests/test-meta.sh assertions become drift detectors, not a
# manual-arithmetic chore.
#
# Usage:
#   feature-registry.sh generate [outfile]   # default: docs/FEATURES.md

set -euo pipefail
export LC_ALL=C

KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# frontmatter field: first `key: value` line inside the first --- pair
fm_field() { # <file> <key>
  awk -v k="$2" '
    /^---$/ { c++; next }
    c == 1 && index($0, k ":") == 1 { sub("^" k ":[[:space:]]*", ""); print; exit }
    c >= 2 { exit }' "$1"
}

# escape pipes and clip to one table-safe line
clip() { # <text>
  local s="$1"
  s="${s#\"}"; s="${s%\"}"
  s="${s//|/\\|}"
  if [ "${#s}" -gt 140 ]; then printf '%s…' "${s:0:139}"; else printf '%s' "$s"; fi
}

# exact-token pattern: hyphens are part of the token, so `review` never matches
# inside `review-team`
token_pat() { printf '(^|[^A-Za-z0-9_-])%s([^A-Za-z0-9_-]|$)' "$1"; }

# stdin: one item per line -> "a, b, c" or "a, b, c +N" or "-"
cap_list() {
  awk 'NR<=3 { if (NR>1) printf ", "; printf "%s", $0 } END {
    if (NR==0) printf "-";
    if (NR>3) printf " +%d", NR-3;
    print "" }'
}

spec_refs() { # <token-pattern>
  grep -lE "$1" "$KIT_DIR"/docs/specs/SPEC-*.md 2>/dev/null \
    | sed -E 's|.*/SPEC-([0-9]+)-.*|SPEC-\1|' | sort -uV | cap_list
}

test_refs() { # <token-pattern>
  grep -lE "$1" "$KIT_DIR"/tests/*.sh 2>/dev/null \
    | sed -E 's|.*/||' | sort -u | cap_list
}

dispatched_by() { # <token-pattern>
  {
    grep -lE "$1" "$KIT_DIR"/commands/*.md 2>/dev/null \
      | sed -E 's|.*/||; s|\.md$||'
    grep -lE "$1" "$KIT_DIR"/skills/*/SKILL.md 2>/dev/null \
      | sed -E 's|/SKILL\.md$||; s|.*/||; s|$| (skill)|'
  } | sort -u | cap_list
}

hook_events() { # <basename.sh>
  local ev
  ev=$(jq -r --arg f "hooks/$1" '
        .hooks | to_entries[] | .key as $k | .value[] | .hooks[]
        | select(.command | endswith($f)) | $k' \
        "$KIT_DIR/hooks/hooks.json" 2>/dev/null | sort -u \
      | awk 'NR>1 {printf "+"} {printf "%s", $0} END {print ""}')
  if [ -z "$ev" ] && jq -r '.statusLine.command // ""' "$KIT_DIR/settings.json" 2>/dev/null \
      | grep -q "$1"; then
    ev="StatusLine"
  fi
  printf '%s' "${ev:--}"
}

hook_desc() { # <file>
  # header-comment convention: `# <name>.sh -- <description>`; fallback: the first
  # comment line with the `<name>.sh` prefix (and its separator) stripped
  local d
  d="$(awk -F' -- ' '/^# / && / -- / { print $2; exit }' "$1")"
  if [ -z "$d" ]; then
    d="$(awk '/^# / { sub(/^# /, ""); print; exit }' "$1" \
      | sed -E "s/^$(basename "$1")[[:space:]]*[,-]*[[:space:]]*//; s/^\xe2\x80\x94[[:space:]]*//")"
  fi
  printf '%s' "$d"
}

commands_table() {
  echo "## Commands"
  echo ""
  echo "| Command | Trigger | Description | Specs | Tests |"
  echo "|---|---|---|---|---|"
  local f name dmi trig pat
  for f in "$KIT_DIR"/commands/*.md; do
    name="$(basename "$f" .md)"
    dmi="$(fm_field "$f" disable-model-invocation)"
    trig='[H/I]'; [ "$dmi" = "true" ] && trig='[H]'
    pat="$(token_pat "$name")"
    printf '| `/kit:%s` | `%s` | %s | %s | %s |\n' \
      "$name" "$trig" "$(clip "$(fm_field "$f" description)")" \
      "$(spec_refs "$pat")" "$(test_refs "$pat")"
  done
  echo ""
}

agents_table() {
  echo "## Agents"
  echo ""
  echo "| Agent | Trigger | Dispatched by | Description | Specs | Tests |"
  echo "|---|---|---|---|---|---|"
  local f name pat
  for f in "$KIT_DIR"/agents/*.md; do
    name="$(basename "$f" .md)"
    pat="$(token_pat "$name")"
    printf '| `%s` | `[D]` | %s | %s | %s | %s |\n' \
      "$name" "$(dispatched_by "$pat")" \
      "$(clip "$(fm_field "$f" description)")" \
      "$(spec_refs "$pat")" "$(test_refs "$pat")"
  done
  echo ""
}

skills_table() {
  echo "## Skills"
  echo ""
  echo "| Skill | Trigger | Description | Specs | Tests |"
  echo "|---|---|---|---|---|"
  local f name dmi trig pat
  for f in "$KIT_DIR"/skills/*/SKILL.md; do
    name="$(basename "$(dirname "$f")")"
    dmi="$(fm_field "$f" disable-model-invocation)"
    trig='[I]'; [ "$dmi" = "true" ] && trig='[H]'
    pat="$(token_pat "$name")"
    printf '| `%s` | `%s` | %s | %s | %s |\n' \
      "$name" "$trig" "$(clip "$(fm_field "$f" description)")" \
      "$(spec_refs "$pat")" "$(test_refs "$pat")"
  done
  echo ""
}

hooks_table() {
  echo "## Hooks"
  echo ""
  echo "| Hook | Trigger | Event | Description | Specs | Tests |"
  echo "|---|---|---|---|---|---|"
  local f base name pat
  for f in "$KIT_DIR"/hooks/*.sh; do
    base="$(basename "$f")"
    name="$(basename "$f" .sh)"
    pat="$(token_pat "$name")"
    printf '| `%s` | `[E]` | %s | %s | %s | %s |\n' \
      "$base" "$(hook_events "$base")" "$(clip "$(hook_desc "$f")")" \
      "$(spec_refs "$pat")" "$(test_refs "$pat")"
  done
  echo ""
}

generate() {
  local out="${1:-$KIT_DIR/docs/FEATURES.md}"
  local tmp="$out.tmp.$$"
  # expand $tmp NOW: the trap fires at script exit, after the local is gone
  trap "rm -f '$tmp'" EXIT
  {
    echo "---"
    echo "title: Feature registry"
    echo "status: GENERATED projection"
    echo "generator: lib/registry/feature-registry.sh"
    echo "---"
    echo ""
    echo "# Feature registry"
    echo ""
    echo "GENERATED , do not hand-edit. Regenerate: \`bash lib/registry/feature-registry.sh generate\`. One row per live feature; freshness pinned by \`tests/test-meta.sh\` (regenerate-and-diff). Trigger classes per \`docs/workflow-paths.md\` section 1: \`[H]\` human-typed, \`[H/I]\` human-or-intent, \`[I]\` intent-read, \`[E]\` event-fired, \`[D]\` dispatched. Refs are exact-token greps: Specs over \`docs/specs/\`, Tests over \`tests/*.sh\`, Dispatched-by over \`commands/*.md\` + \`skills/*/SKILL.md\` (skill dispatchers marked \`(skill)\`); \`-\` means no reference found (a coverage gap, not always a defect: read-only agents may be deliberately untested)."
    echo ""
    commands_table
    agents_table
    skills_table
    hooks_table
  } > "$tmp"
  mv -f "$tmp" "$out"
  sync_counts
}

# Patches the hand-maintained "N commands / N agents / ..." count strings in
# README.md and docs/architecture.md to the live file counts. Everything here
# is arithmetic derived from `ls`; no judgment, no prose to write. Table ROWS
# (one sentence per command/agent) still need a human , this only kills the
# recompute-and-retype-the-numbers step.
sync_counts() {
  local cmd_count agt_count hook_count skill_count total
  cmd_count=$(ls "$KIT_DIR"/commands/*.md 2>/dev/null | wc -l | tr -d ' ')
  agt_count=$(ls "$KIT_DIR"/agents/*.md 2>/dev/null | wc -l | tr -d ' ')
  hook_count=$(ls "$KIT_DIR"/hooks/*.sh 2>/dev/null | wc -l | tr -d ' ')
  skill_count=$(ls "$KIT_DIR"/skills/*/SKILL.md 2>/dev/null | wc -l | tr -d ' ')
  total=$((cmd_count + agt_count))

  local readme="$KIT_DIR/README.md"
  local rtmp="$readme.tmp.$$"
  trap "rm -f '$rtmp'" EXIT
  sed -E \
    -e "s/(agents\/ *\()[0-9]+( files)/\\1${agt_count}\\2/" \
    -e "s/(commands\/ *\()[0-9]+( markdown)/\\1${cmd_count}\\2/" \
    -e "s/(hooks\/ *\()[0-9]+( scripts)/\\1${hook_count}\\2/" \
    -e "s/(<b>Agents<\/b> \()[0-9]+(,)/\\1${agt_count}\\2/" \
    -e "s/(<b>Commands<\/b> \()[0-9]+(,)/\\1${cmd_count}\\2/" \
    -e "s/(<b>Skills<\/b> \()[0-9]+(,)/\\1${skill_count}\\2/" \
    -e "s/(<b>Hooks<\/b> \()[0-9]+(,)/\\1${hook_count}\\2/" \
    "$readme" > "$rtmp"
  mv -f "$rtmp" "$readme"

  local arch="$KIT_DIR/docs/architecture.md"
  local atmp="$arch.tmp.$$"
  trap "rm -f '$rtmp' '$atmp'" EXIT
  # drops the untested "(N build · N code · ...)" phase breakdown: it drifted
  # silently (no test ever checked it) and the inventory table above already
  # shows each entry's Arm; keeping a second, unverified tally of the same
  # data was pure toil for zero signal.
  sed -E \
    -e "s/^Total: [0-9]+ commands \+ [0-9]+ agents = \*\*[0-9]+ entries\*\*.*/Total: ${cmd_count} commands + ${agt_count} agents = **${total} entries**./" \
    "$arch" > "$atmp"
  mv -f "$atmp" "$arch"
}

case "${1:-}" in
  generate) shift; generate "$@" ;;
  *) echo "usage: feature-registry.sh generate [outfile]" >&2; exit 64 ;;
esac
