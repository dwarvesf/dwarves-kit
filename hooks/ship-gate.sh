#!/bin/bash
# ship-gate.sh, PreToolUse hook, matcher: Bash
# Workflow-completeness gate at the ship/push boundary (ADR-0024). When a feature
# branch is pushed or a PR is opened, refuse if the active spec's lane has a
# required (measure-twice) gate with no `ran`/`override` entry in its run ledger.
#
# This is a QUALITY gate, not a safety gate: it FAILS OPEN on any ambiguity (no
# repo, no spec, no lane, missing tooling) so a bug here can never block unrelated
# work. push-to-main and force-push stay safety-gate.sh's job. Exit 2 = block.
set -uo pipefail
INPUT=$(cat)
CMD=$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
[ -z "$CMD" ] && exit 0

# Engage only on a ship action: a git push or a gh pr create.
echo "$CMD" | grep -qE 'git[[:space:]]+push|gh[[:space:]]+pr[[:space:]]+create' || exit 0
# Leave push-to-main / force-push to safety-gate; do not double-handle.
echo "$CMD" | grep -qE '\b(main|master)\b|--force' && exit 0

ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -n "$ROOT" ] || exit 0
BRANCH=$(git -C "$ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
[ -n "$BRANCH" ] || exit 0
SLUG="${BRANCH#*/}"   # strip the type/ prefix (feat/, docs/, ...)

# Resolve the spec for this slug; fail open if there is no spec-driven run.
SPEC=$(ls "$ROOT"/docs/specs/SPEC-*-"$SLUG".md 2>/dev/null | head -1 || true)
[ -n "$SPEC" ] || exit 0
LANE=$(grep -m1 -iE '^Lane:' "$SPEC" 2>/dev/null | sed -E 's/^[Ll]ane:[[:space:]]*//; s/[[:space:]].*$//' || true)
[ -n "$LANE" ] || exit 0

LEDGER="${CLAUDE_PLUGIN_ROOT:-$ROOT}/lib/gate-ledger.sh"
[ -f "$LEDGER" ] || exit 0

if ! GAPS=$(bash "$LEDGER" check "$LANE" "$SLUG" 2>&1); then
  LOG_DIR="${DWARVES_KIT_LOG_DIR:-$HOME/.claude/dwarves-kit/logs}"
  mkdir -p "$LOG_DIR" 2>/dev/null || true
  echo "$(date -u +%Y-%m-%dT%H:%M:%SZ) | BLOCKED | ship-gate | $SLUG ($LANE)" >> "$LOG_DIR/ship-gate.log" 2>/dev/null || true
  {
    echo "BLOCKED: ship-gate. The '$LANE' lane requires gates that have not run for spec '$SLUG':"
    printf '%s\n' "$GAPS" | sed 's/^/  /'
    echo "Run the missing gate(s), or log an explicit override (recorded for audit):"
    echo "  bash \"$LEDGER\" override $SLUG <phase> \"<reason>\""
  } >&2
  exit 2
fi
exit 0
