#!/usr/bin/env bash
# always: a new suite that reaches the config resolver is flagged even when the diff names no existing suite
# test-operator-pin.sh -- a suite that reaches the config resolver fences off the host operator layer.
#
# The operator kit.toml (${XDG_CONFIG_HOME:-$HOME/.config}/dwarves-kit/kit.toml) is a per-machine
# preference layer. A suite that inherits it asserts the maintainer's taste, not the kit's default,
# and goes red on a host whose operator file sets a knob (the adopt.single_source incident).
#
# Rule 1: every suite whose text reaches the resolver (config, adopt, wrap, gate-ledger, lane data,
#         hook-module, ...) pins KIT_CONFIG_OPERATOR, XDG_CONFIG_HOME or HOME, in its own code or in
#         a tests/lib helper it sources. A comment does not count.
#         An exemption is one line in the suite: `# operator-layer: unpinned-ok <reason>`.
# Rule 2: both suite runners (tests/run-all.sh, bin/test-affected) pin it for every suite they
#         start, so an indirect reach the pattern cannot see is fenced too.
#
# The reach pattern is a name match, not a call-graph walk, so it can over-flag (a suite that only
# mentions adopt.sh in a string). Over-flagging costs one export line; under-flagging costs a red
# suite on somebody else's machine.
#
# Run: bash tests/test-operator-pin.sh
set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-operator-pin-none.$$"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS  %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL  %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }

REACH_RE='kit-config\.sh|kit_config_get|bin/config|lib/config/|adopt\.sh|bin/wrap|lib/wrap|gate-ledger\.sh|lane-data|hook-module|kit_hook_enabled|config\.sh'
PIN_RE='KIT_CONFIG_OPERATOR|XDG_CONFIG_HOME|(^|[^A-Za-z_])HOME=|export HOME'

# code_of <file>: the file without comment lines.
code_of() { grep -vE '^[[:space:]]*#' "$1" 2>/dev/null; }

# unpinned_suites <libdir> <suite>...: the suites that reach the resolver and pin nothing. A suite
# that names a helper under <libdir> (source or call) counts the helper's code as its own.
unpinned_suites() {
  local libdir="$1"; shift
  local f text helper
  for f in "$@"; do
    [ -f "$f" ] || continue
    grep -q '^# operator-layer: unpinned-ok' "$f" && continue
    text="$(code_of "$f")"
    for helper in "$libdir"/*.sh; do
      [ -f "$helper" ] || continue
      grep -qF -- "$(basename "$helper")" <<<"$text" && text="$text"$'\n'"$(code_of "$helper")"
    done
    grep -qE "$REACH_RE" <<<"$text" || continue
    grep -qE "$PIN_RE" <<<"$text" || printf '%s\n' "$f"
  done
}

# --- the live tree ---------------------------------------------------------------------------
echo "== rule 1: every suite that reaches the resolver pins the operator layer =="
cd "$KIT_DIR" || exit 1
source tests/lib/suites.sh
SUITES=(); while IFS= read -r s; do SUITES+=("$s"); done < <(suite_list)
LEFT="$(unpinned_suites tests/lib "${SUITES[@]}")"
eq "no suite reaches the resolver unpinned (${#SUITES[@]} suites scanned)" "$LEFT" ""

# --- the guard catches what it claims to -----------------------------------------------------
echo "== the check itself =="
FX="$(mktemp -d "${TMPDIR:-/tmp}/kit-operator-pin.XXXXXX")" || exit 1
trap 'rm -rf "$FX"' EXIT
mkdir -p "$FX/lib"
printf 'export KIT_CONFIG_OPERATOR=/nowhere\n' > "$FX/lib/pin-helper.sh"
printf '#!/bin/bash\nbash bin/config get x\n' > "$FX/reach-unpinned.sh"
printf '#!/bin/bash\nexport KIT_CONFIG_OPERATOR=/nowhere\nbash bin/config get x\n' > "$FX/reach-pinned.sh"
printf '#!/bin/bash\nsource lib/pin-helper.sh\nbash bin/config get x\n' > "$FX/reach-helper-pinned.sh"
printf '#!/bin/bash\n# KIT_CONFIG_OPERATOR is not set here\nbash bin/config get x\n' > "$FX/reach-comment-only.sh"
printf '#!/bin/bash\n# operator-layer: unpinned-ok the suite builds its own HOME in a subshell helper\nbash bin/config get x\n' > "$FX/reach-exempt.sh"
printf '#!/bin/bash\nHOME=/tmp/x bash bin/config get x\n' > "$FX/reach-home-pinned.sh"
printf '#!/bin/bash\nREAL_HOME=/tmp/x bash bin/config get x\n' > "$FX/reach-real-home-only.sh"
printf '#!/bin/bash\necho nothing to see\n' > "$FX/no-reach.sh"
GOT="$(cd "$FX" && unpinned_suites lib reach-unpinned.sh reach-pinned.sh reach-helper-pinned.sh reach-comment-only.sh reach-exempt.sh reach-home-pinned.sh reach-real-home-only.sh no-reach.sh | LC_ALL=C sort | tr '\n' ' ')"
eq "flags exactly the unpinned reach (bare, comment-only, REAL_HOME= lookalike)" "$GOT" "reach-comment-only.sh reach-real-home-only.sh reach-unpinned.sh "

# --- rule 2: the runners pin it ---------------------------------------------------------------
echo "== rule 2: both runners pin the operator layer for every suite =="
for runner in tests/run-all.sh bin/test-affected; do
  n="$(code_of "$KIT_DIR/$runner" | grep -cE 'KIT_CONFIG_OPERATOR=')"
  if [ "$n" -ge 1 ]; then ok "$runner pins KIT_CONFIG_OPERATOR for the suites it starts"; else bad "$runner does not pin KIT_CONFIG_OPERATOR"; fi
done

echo
echo "operator-pin: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
