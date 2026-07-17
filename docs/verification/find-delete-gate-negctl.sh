#!/bin/bash
# Negative control for the find-delete gate fix.
# Payloads live here (not on the caller's command line) so the live gate does not
# fire on the harness that is testing it.
cd ~/workspace/tieubao/dwarves-kit || exit 1
export DWARVES_KIT_LOG_DIR=$(mktemp -d)

INCIDENT='find ~/.cache/.bun -mindepth 1 -delete 2>/dev/null'
CONTROL_BLOCK='rm -r'' -f src'          # split so this file's own text is inert
CONTROL_ALLOW='find node_modules -mindepth 1 -delete'

probe() {  # <command-string>
  jq -nc --arg c "$1" '{tool_input:{command:$c}}' \
    | bash hooks/safety-gate.sh >/dev/null 2>&1
  echo $?
}

row() { printf '  %-34s exit=%s (want %s)\n' "$2" "$(probe "$1")" "$3"; }

echo "### STEP 1 -- fix in place (HEAD)"
echo "  sha: $(shasum hooks/safety-gate.sh | cut -c1-12)"
row "$INCIDENT"      "incident: find -delete"   2
row "$CONTROL_BLOCK" "control: recursive-force rm" 2
row "$CONTROL_ALLOW" "control: find on artifact" 0

echo "### STEP 2 -- NEGATIVE CONTROL: revert hook to pre-fix (HEAD~1)"
git checkout HEAD~1 -- hooks/safety-gate.sh
echo "  sha: $(shasum hooks/safety-gate.sh | cut -c1-12)  <- must differ from step 1"
row "$INCIDENT"      "incident: find -delete"   0
row "$CONTROL_BLOCK" "control: recursive-force rm" 2
row "$CONTROL_ALLOW" "control: find on artifact" 0

echo "### STEP 3 -- RESTORE (HEAD)"
git checkout HEAD -- hooks/safety-gate.sh
echo "  sha: $(shasum hooks/safety-gate.sh | cut -c1-12)  <- must match step 1"
row "$INCIDENT"      "incident: find -delete"   2
row "$CONTROL_BLOCK" "control: recursive-force rm" 2
row "$CONTROL_ALLOW" "control: find on artifact" 0

echo "### tree clean?"
git status --porcelain hooks/safety-gate.sh
echo "(clean if nothing above)"
