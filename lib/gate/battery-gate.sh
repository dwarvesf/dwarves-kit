#!/usr/bin/env bash
# battery-gate.sh -- size gate for /kit:battery. ADVISORY: prints one line and ALWAYS exits 0.
#
# A small single-purpose change does not earn three fresh-context subagents; it owes a proof of
# done (captured output). The lane classifier cannot say "small" (normal is the default lane and
# carries no size signal), so this counts the diff.
#
# Usage: battery-gate.sh <root> [<base>]
#   RUN                                   -> run the battery
#   SKIP: small change (<n> changed lines, <f> files); owe proof of done, not the battery
#
# Small = changed lines (base...HEAD plus the working tree, markdown and docs/verification/**
# excluded) under the floor AND no hard path hit (`lane-classify.sh floor`: a hard path always
# RUNs). Floor: BATTERY_SMALL_FLOOR env, else `[battery] size_floor` in .kit.toml, else 150.
set -uo pipefail
GATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LC="$GATE_DIR/../classify/lane-classify.sh"
# shellcheck source=lib/classify/lane-classify.sh
. "$LC"; set +e
# shellcheck source=lib/config/kit-config.sh
. "$GATE_DIR/../config/kit-config.sh"

root="${1:-}"
[ -n "$root" ] || { echo "usage: battery-gate.sh <root> [<base>]" >&2; exit 64; }
base="${2:-}"
if [ -n "$base" ]; then
  base="$(git -C "$root" merge-base HEAD "$base" 2>/dev/null || printf '%s' "$base")"
else
  base="$(_deesc_resolve_base "$root")"
fi
[ -n "$base" ] || { echo RUN; exit 0; }

floor="${BATTERY_SMALL_FLOOR:-$(KIT_PROJECT_ROOT="$root" kit_config_get battery.size_floor 150)}"
[[ "$floor" =~ ^[0-9]+$ ]] || floor=150

[ -z "$(bash "$LC" floor "$root" "$base" 2>/dev/null)" ] || { echo RUN; exit 0; }

excl=(':(exclude)*.md' ':(exclude)docs/verification/**')
lines="$(_deesc_changed_lines "$root" "$base" "${excl[@]}")"
[[ "$lines" =~ ^[0-9]+$ ]] || { echo RUN; exit 0; }
files="$({ git -C "$root" diff --name-only "$base"..HEAD -- . "${excl[@]}"
           git -C "$root" diff --name-only HEAD -- . "${excl[@]}"; } 2>/dev/null | sort -u | grep -c .)"

if [ "$lines" -lt "$floor" ]; then
  echo "SKIP: small change ($lines changed lines, $files files); owe proof of done, not the battery"
else
  echo RUN
fi
exit 0
