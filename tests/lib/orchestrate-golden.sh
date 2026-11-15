#!/usr/bin/env bash
# orchestrate-golden.sh -- print the orchestrator's observable output for a fixed mega-goal: the
# `run --dry-run` plan and the `_wave_converge` console, events and merge-hook argv. Deterministic:
# no network, tmp paths and timestamps normalised, config pinned to an empty layer.
# tests/fixtures/orchestrate-golden/off.txt was captured from this script on master before any
# tiered-verification edit; test-orchestrate-tiered.sh C9 diffs a fresh run against it.
# Usage: bash tests/lib/orchestrate-golden.sh [<kit-root>]
set -uo pipefail
KIT="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/kit-golden.XXXXXX")" || exit 1
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/cfg-root" "$TMP/cfg-op" "$TMP/proj"
: > "$TMP/cfg-root/kit.toml"
export KIT_CONFIG_ROOT="$TMP/cfg-root" KIT_CONFIG_OPERATOR="$TMP/cfg-op" KIT_PROJECT_ROOT="$TMP/proj"
export WAVE_CAP=2 WAVE_ROLLING=0 MULTIPLEXER=0 PANE_VIEWER=none TURN_CAP=300

REPO="$TMP/repo"; MG="$REPO/mega"
mkdir -p "$MG/goals"
git -C "$REPO" init -q 2>/dev/null
git -C "$REPO" config user.email t@example.com
git -C "$REPO" config user.name test
git -C "$REPO" commit -q --allow-empty -m init
cat > "$MG/ROADMAP.md" <<'EOF'
# Mega-goal: golden
## Sub-goals
- [ ] SG-01 alpha , auto , PR #11
- [ ] SG-02 beta , auto , PR #12
- [ ] SG-03 gamma , gate , PR #__
EOF
echo "POINTER: resume from ROADMAP" > "$MG/POINTER_PROMPT.md"
printf '# SG-01: alpha\n**Branch:** feat/alpha\n\n## Touches\n- a.txt\n' > "$MG/goals/01-SG-01.md"
printf '# SG-02: beta\n**Branch:** feat/beta\n\n## Touches\n- b.txt\n' > "$MG/goals/02-SG-02.md"

cat > "$TMP/hook" <<'EOF'
#!/usr/bin/env bash
echo "$*" >> "$HOOK_LOG"
exit "${MOCK_RC:-0}"
EOF
cat > "$TMP/gh" <<'EOF'
#!/usr/bin/env bash
[ "$1 $2" = "pr view" ] && { echo "${GH_STATE:-OPEN}"; exit 0; }
exit 1
EOF
chmod +x "$TMP/hook" "$TMP/gh"
export HOOK_LOG="$TMP/hook.log" MEGA_MERGE_GH="$TMP/gh" WAVE_MERGE_CMD="$TMP/hook"

norm() { sed -e "s#$TMP#<TMP>#g"; }

echo "== run --dry-run"
bash "$KIT/lib/queue/orchestrate.sh" run "$MG" --dry-run --board=roadmap 2>&1 | norm

converge_case() {  # <label> <env assignments...>
  local label="$1"; shift
  rm -rf "$MG/.orchestrate"; : > "$HOOK_LOG"
  echo "== converge: $label"
  env "$@" bash -c 'source "$1/lib/queue/orchestrate.sh"; _wave_converge "$2" SG-01 SG-02; echo "rc=$?"' _ "$KIT" "$MG" 2>&1 | norm
  echo "-- events"
  cut -f2- "$MG/.orchestrate/events.log" 2>/dev/null | norm
  echo "-- hook argv"
  cat "$HOOK_LOG" | norm
}
converge_case merged GH_STATE=MERGED
converge_case dry-run GH_STATE=OPEN
converge_case hook-failure GH_STATE=MERGED MOCK_RC=3
