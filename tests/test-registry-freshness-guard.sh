#!/usr/bin/env bash
# test-registry-freshness-guard.sh -- the registry check verb, and the pre-push arm
# that calls it. Cases 1-3 drive lib/registry/feature-registry.sh directly; cases
# 4-10 drive hooks/ship-gate.sh with crafted stdin, same harness shape as
# tests/test-ship-gate-fail-closed.sh.
#
# Every fixture is a throwaway repo carrying a COPY of the generator, so the
# generator's KIT_DIR resolves to the fixture and it scans a handful of stub files
# instead of the whole kit. That keeps each case well under a second; the real
# ~20s regen is exercised once by tests/test-meta.sh's freshness pin.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

LOGDIR="$(mktemp -d)"
REG="lib/registry/feature-registry.sh"

# A fixture repo that looks like the kit to the gate's file-existence scoping:
# the generator, a generated projection, and one stub feature of each kind the
# generator walks.
mkkit() { # $1=dir
  local d="$1"
  git init -q -b master "$d"
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  mkdir -p "$d/lib/registry" "$d/commands" "$d/agents" "$d/skills/demo" "$d/hooks" "$d/docs/specs" "$d/tests"
  cp "$KIT/$REG" "$d/$REG"
  printf -- '---\ndescription: a stub command\n---\nbody\n' > "$d/commands/demo.md"
  printf -- '---\ndescription: a stub agent\n---\nbody\n' > "$d/agents/demo-agent.md"
  printf -- '---\ndescription: a stub skill\n---\nbody\n' > "$d/skills/demo/SKILL.md"
  printf '#!/bin/bash\n# demo-hook.sh -- a stub hook\n' > "$d/hooks/demo-hook.sh"
  printf '{"hooks":{}}\n' > "$d/hooks/hooks.json"
  printf '{}\n' > "$d/settings.json"
  ( cd "$d" && bash "$REG" generate docs/FEATURES.md )
  git -C "$d" add -A; git -C "$d" commit -qm init
}

gate() { # $1=repo  -> echoes exit code, stderr to $2
  ( cd "$1" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
      | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" \
        bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"${2:-/dev/null}"; echo $? )
}

# --- the check verb ----------------------------------------------------------

T1="$(mktemp -d)/kit"; mkkit "$T1"

# 1. fresh projection -> exit 0
( cd "$T1" && bash "$REG" check docs/FEATURES.md >/dev/null 2>&1 )
[ $? -eq 0 ] && ok "check on a fresh projection exits 0" || no "fresh check should exit 0"

# 2. stale projection -> exit 1, and the message names the file
printf '\n| `stale` | `[X]` | hand-edited row |\n' >> "$T1/docs/FEATURES.md"
OUT2="$( cd "$T1" && bash "$REG" check docs/FEATURES.md 2>&1 )"; RC2=$?
[ "$RC2" -eq 1 ] && ok "check on a stale projection exits 1" || no "stale check should exit 1 (got $RC2)"
printf '%s' "$OUT2" | grep -q 'docs/FEATURES.md' \
  && ok "the stale summary names docs/FEATURES.md" || no "stale summary should name the file"

# 3. --fix regenerates in place and exits 0
( cd "$T1" && bash "$REG" check --fix docs/FEATURES.md >/dev/null 2>&1 )
RC3=$?
( cd "$T1" && bash "$REG" check docs/FEATURES.md >/dev/null 2>&1 )
[ "$RC3" -eq 0 ] && [ $? -eq 0 ] \
  && ok "check --fix regenerates in place and leaves it fresh" || no "--fix should regenerate and exit 0"

# --- the pre-push arm --------------------------------------------------------

# 4. an input moved, the projection did not -> BLOCKED (exit 2).
# Adding a test file that names a feature moves that feature's Tests column,
# which is the exact shape of the incident this gate exists for.
T4="$(mktemp -d)/kit"; mkkit "$T4"
git -C "$T4" switch -qc feat/frg-stale
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T4/tests/test-frg.sh"
git -C "$T4" add -A; git -C "$T4" commit -qm "add a test naming a feature"
ERR4="$(mktemp)"
RC4="$(gate "$T4" "$ERR4")"
[ "$RC4" = 2 ] && ok "input moved + stale projection -> blocked (exit 2)" \
  || no "stale input-touching push should block (got $RC4)"

# 5. the refusal names the regenerate command
grep -q 'feature-registry.sh generate docs/FEATURES.md' "$ERR4" \
  && ok "the refusal names the regenerate command" || no "refusal should name the regenerate command"

# 6. the same branch, once the projection is regenerated -> passes
( cd "$T4" && bash "$REG" generate docs/FEATURES.md )
git -C "$T4" add -A; git -C "$T4" commit -qm regen
[ "$(gate "$T4")" = 0 ] && ok "input moved + regenerated projection -> pass (exit 0)" \
  || no "regenerated branch should pass"

# 7. the diff carries docs/FEATURES.md but it is STALE -> the regen is skipped,
# so the arm passes. tests/test-meta.sh pins that case in CI instead.
T7="$(mktemp -d)/kit"; mkkit "$T7"
git -C "$T7" switch -qc feat/frg-shortcircuit
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T7/tests/test-frg.sh"
printf '\n| `stale` | `[X]` | hand-edited row |\n' >> "$T7/docs/FEATURES.md"
git -C "$T7" add -A; git -C "$T7" commit -qm "input + a stale hand edit"
[ "$(gate "$T7")" = 0 ] && ok "diff carries docs/FEATURES.md -> regen skipped, pass (exit 0)" \
  || no "a diff carrying FEATURES.md should skip the regen"

# 8. a diff touching no input -> never gated, even with a stale projection.
# The stale row lands on master, so the branch diff carries neither an input nor
# docs/FEATURES.md and the arm must stay out of the way regardless.
T8="$(mktemp -d)/kit"; mkkit "$T8"
printf '\n| `stale` | `[X]` | hand-edited row |\n' >> "$T8/docs/FEATURES.md"
git -C "$T8" add -A; git -C "$T8" commit -qm "a stale row on master"
git -C "$T8" switch -qc feat/frg-noinput
printf 'notes\n' > "$T8/NOTES.txt"
git -C "$T8" add -A; git -C "$T8" commit -qm "a non-input file"
[ "$(gate "$T8")" = 0 ] && ok "diff touching no input -> not gated (exit 0)" \
  || no "a non-input diff should not be gated"

# 9. the escape hatch skips the arm on the case-4 shape
T9="$(mktemp -d)/kit"; mkkit "$T9"
git -C "$T9" switch -qc feat/frg-escape
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T9/tests/test-frg.sh"
git -C "$T9" add -A; git -C "$T9" commit -qm "add a test naming a feature"
RC9="$( cd "$T9" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
  | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1 \
    bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>&1; echo $? )"
[ "$RC9" = 0 ] && ok "DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1 skips the arm (exit 0)" \
  || no "the escape hatch should skip the arm (got $RC9)"

# 10. a repo with no generator is never gated (the consumer-repo scoping)
T10="$(mktemp -d)/repo"; mkkit "$T10"
git -C "$T10" switch -qc feat/frg-consumer
git -C "$T10" rm -q -r lib
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T10/tests/test-frg.sh"
git -C "$T10" add -A; git -C "$T10" commit -qm "no generator here"
[ "$(gate "$T10")" = 0 ] && ok "repo without the generator is not gated (exit 0)" \
  || no "a repo with no generator should not be gated"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
