#!/usr/bin/env bash
# test-registry-freshness-guard.sh -- the registry check verb, and the pre-push arm
# that calls it. Cases 1-3 drive lib/registry/feature-registry.sh directly; cases
# 4-10 drive hooks/ship-gate.sh with crafted stdin, same harness shape as
# tests/test-ship-gate-fail-closed.sh.
#
# Every fixture is a throwaway repo carrying a COPY of the generator, so the
# generator's KIT_DIR resolves to the fixture and it scans a handful of stub files
# instead of the whole kit. That keeps each case well under a second; the real
# ~4s regen is exercised once by tests/test-meta.sh's freshness pin.
set -uo pipefail
KIT="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

LOGDIR="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
REG="lib/registry/feature-registry.sh"

# A fixture repo that looks like the kit to the gate's file-existence scoping:
# the generator, a generated projection, and one stub feature of each kind the
# generator walks.
mkkit() { # $1=dir
  local d="$1"
  git init -q -b master "$d"
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  mkdir -p "$d/lib/registry" "$d/commands" "$d/agents" "$d/skills/demo" "$d/hooks" "$d/docs/specs" "$d/docs/reference" "$d/tests"
  cp "$KIT/$REG" "$d/$REG"
  printf -- '---\ndescription: a stub command\n---\nbody\n' > "$d/commands/demo.md"
  printf -- '---\ndescription: a stub agent\n---\nbody\n' > "$d/agents/demo-agent.md"
  printf -- '---\ndescription: a stub skill\n---\nbody\n' > "$d/skills/demo/SKILL.md"
  printf '#!/bin/bash\n# demo-hook.sh -- a stub hook\n' > "$d/hooks/demo-hook.sh"
  printf '{"hooks":{}}\n' > "$d/hooks/hooks.json"
  printf '{}\n' > "$d/settings.json"
  ( cd "$d" && bash "$REG" generate docs/reference/FEATURES.md )
  git -C "$d" add -A; git -C "$d" commit -qm init
}

gate() { # $1=repo  -> echoes exit code, stderr to $2
  ( cd "$1" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
      | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" \
        bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"${2:-/dev/null}"; echo $? )
}

# --- the check verb ----------------------------------------------------------

T1="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T1="$T1/kit"; mkkit "$T1"

# 1. fresh projection -> exit 0
( cd "$T1" && bash "$REG" check docs/reference/FEATURES.md >/dev/null 2>&1 )
[ $? -eq 0 ] && ok "check on a fresh projection exits 0" || no "fresh check should exit 0"

# 2. stale projection -> exit 1, and the message names the file
printf '\n| `stale` | `[X]` | hand-edited row |\n' >> "$T1/docs/reference/FEATURES.md"
OUT2="$( cd "$T1" && bash "$REG" check docs/reference/FEATURES.md 2>&1 )"; RC2=$?
[ "$RC2" -eq 1 ] && ok "check on a stale projection exits 1" || no "stale check should exit 1 (got $RC2)"
printf '%s' "$OUT2" | grep -q 'docs/reference/FEATURES.md' \
  && ok "the stale summary names docs/reference/FEATURES.md" || no "stale summary should name the file"

# 3. --fix regenerates in place and exits 0
( cd "$T1" && bash "$REG" check --fix docs/reference/FEATURES.md >/dev/null 2>&1 )
RC3=$?
( cd "$T1" && bash "$REG" check docs/reference/FEATURES.md >/dev/null 2>&1 )
[ "$RC3" -eq 0 ] && [ $? -eq 0 ] \
  && ok "check --fix regenerates in place and leaves it fresh" || no "--fix should regenerate and exit 0"

# --- the pre-push arm --------------------------------------------------------

# 4. an input moved, the projection did not -> BLOCKED (exit 2).
# Adding a test file that names a feature moves that feature's Tests column,
# which is the exact shape of the incident this gate exists for.
T4="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T4="$T4/kit"; mkkit "$T4"
git -C "$T4" switch -qc feat/frg-stale
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T4/tests/test-frg.sh"
git -C "$T4" add -A; git -C "$T4" commit -qm "add a test naming a feature"
ERR4="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
RC4="$(gate "$T4" "$ERR4")"
[ "$RC4" = 2 ] && ok "input moved + stale projection -> blocked (exit 2)" \
  || no "stale input-touching push should block (got $RC4)"

# 5. the refusal names the regenerate command
grep -q 'feature-registry.sh generate docs/reference/FEATURES.md' "$ERR4" \
  && ok "the refusal names the regenerate command" || no "refusal should name the regenerate command"

# 6. the same branch, once the projection is regenerated -> passes
( cd "$T4" && bash "$REG" generate docs/reference/FEATURES.md )
git -C "$T4" add -A; git -C "$T4" commit -qm regen
[ "$(gate "$T4")" = 0 ] && ok "input moved + regenerated projection -> pass (exit 0)" \
  || no "regenerated branch should pass"

# 7. the diff carries docs/reference/FEATURES.md but it is STALE -> the regen is skipped,
# so the arm passes. tests/test-meta.sh pins that case in CI instead.
T7="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T7="$T7/kit"; mkkit "$T7"
git -C "$T7" switch -qc feat/frg-shortcircuit
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T7/tests/test-frg.sh"
printf '\n| `stale` | `[X]` | hand-edited row |\n' >> "$T7/docs/reference/FEATURES.md"
git -C "$T7" add -A; git -C "$T7" commit -qm "input + a stale hand edit"
[ "$(gate "$T7")" = 0 ] && ok "diff carries docs/reference/FEATURES.md -> regen skipped, pass (exit 0)" \
  || no "a diff carrying FEATURES.md should skip the regen"

# 8. a diff touching no input -> never gated, even with a stale projection.
# The stale row lands on master, so the branch diff carries neither an input nor
# docs/reference/FEATURES.md and the arm must stay out of the way regardless.
T8="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T8="$T8/kit"; mkkit "$T8"
printf '\n| `stale` | `[X]` | hand-edited row |\n' >> "$T8/docs/reference/FEATURES.md"
git -C "$T8" add -A; git -C "$T8" commit -qm "a stale row on master"
git -C "$T8" switch -qc feat/frg-noinput
printf 'notes\n' > "$T8/NOTES.txt"
git -C "$T8" add -A; git -C "$T8" commit -qm "a non-input file"
[ "$(gate "$T8")" = 0 ] && ok "diff touching no input -> not gated (exit 0)" \
  || no "a non-input diff should not be gated"

# 9. the escape hatch skips the arm on the case-4 shape
T9="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T9="$T9/kit"; mkkit "$T9"
git -C "$T9" switch -qc feat/frg-escape
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T9/tests/test-frg.sh"
git -C "$T9" add -A; git -C "$T9" commit -qm "add a test naming a feature"
RC9="$( cd "$T9" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
  | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1 \
    bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>&1; echo $? )"
[ "$RC9" = 0 ] && ok "DWARVES_KIT_SKIP_REGISTRY_FRESHNESS=1 skips the arm (exit 0)" \
  || no "the escape hatch should skip the arm (got $RC9)"

# 10. a repo with no generator is never gated (the consumer-repo scoping)
T10="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T10="$T10/repo"; mkkit "$T10"
git -C "$T10" switch -qc feat/frg-consumer
git -C "$T10" rm -q -r lib
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T10/tests/test-frg.sh"
git -C "$T10" add -A; git -C "$T10" commit -qm "no generator here"
[ "$(gate "$T10")" = 0 ] && ok "repo without the generator is not gated (exit 0)" \
  || no "a repo with no generator should not be gated"

# 11. the pushed repo's own generator is never executed: a marker-writing generator
# committed on the base must stay unrun, and the kit's copy still judges the tree.
T11="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T11="$T11/kit"; mkkit "$T11"
M11="$T11.marker"
printf '#!/bin/bash\ntouch "%s"\nexit 0\n' "$M11" > "$T11/$REG"
git -C "$T11" add -A; git -C "$T11" commit -qm "repo-supplied generator"
git -C "$T11" switch -qc feat/frg-hostile
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T11/tests/test-frg.sh"
git -C "$T11" add -A; git -C "$T11" commit -qm "add a test naming a feature"
RC11="$(gate "$T11")"
[ ! -e "$M11" ] && ok "a repo-supplied generator is not executed by the gate" \
  || no "the gate ran the pushed repo's own generator"
[ "$RC11" = 2 ] && ok "the kit's own generator still judges the stale projection (exit 2)" \
  || no "the kit's generator should block the stale projection (got $RC11)"

# 12. the pushed repo's own doc-projection checker is never executed either
T12="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T12="$T12/kit"; mkkit "$T12"
M12="$T12.marker"
mkdir -p "$T12/lib/gate"
printf '#!/bin/bash\ntouch "%s"\nexit 0\n' "$M12" > "$T12/lib/gate/doc-projection-check.sh"
printf '#!/bin/bash\nexit 0\n' > "$T12/tests/test-meta.sh"
git -C "$T12" add -A; git -C "$T12" commit -qm "repo-supplied checker"
git -C "$T12" switch -qc feat/frg-hostile-dp
printf 'contract\n' > "$T12/AGENTS.md"
git -C "$T12" add -A; git -C "$T12" commit -qm "touch a projection surface"
gate "$T12" >/dev/null
[ ! -e "$M12" ] && ok "a repo-supplied doc-projection checker is not executed by the gate" \
  || no "the gate ran the pushed repo's own doc-projection checker"

# 13. a kit install that cannot scan another tree (it predates FEATURE_REGISTRY_ROOT) skips the
# arm with a note instead of calling a fresh projection stale.
OLDKIT="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
cp -R "$KIT/lib" "$OLDKIT/lib"
sed 's/FEATURE_REGISTRY_ROOT/LEGACY_SCAN_ROOT/g' "$KIT/$REG" > "$OLDKIT/$REG"
ERR13="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
RC13="$( cd "$T4" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
  | CLAUDE_PLUGIN_ROOT="$OLDKIT" DWARVES_KIT_LOG_DIR="$LOGDIR" \
    bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"$ERR13"; echo $? )"
[ "$RC13" = 0 ] && grep -q 'registry freshness check skipped' "$ERR13" \
  && ok "an install too old to scan another tree skips the arm with a note (exit 0)" \
  || no "a stale install should skip with a note (got $RC13)"

# 14. a diff touching ONLY a per-lib suite (lib/**/tests/*) that names a feature moves the
# Tests column, so the arm must block it. The 2026-10 incident shape: a recall test edit
# bumped a Tests count and pushed with no regeneration because the trigger list
# stopped at tests/test-*.sh.
T14="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T14="$T14/kit"; mkkit "$T14"
git -C "$T14" switch -qc feat/frg-libtest
mkdir -p "$T14/lib/demo/tests"
printf 'def test_x():\n    assert "demo-agent"\n' > "$T14/lib/demo/tests/test_demo.py"
git -C "$T14" add -A; git -C "$T14" commit -qm "a lib-suite test naming a feature"
[ "$(git -C "$T14" diff --name-only master HEAD | tr '\n' ' ')" = "lib/demo/tests/test_demo.py " ] \
  && ok "fixture diff carries only the lib/**/tests file" || no "fixture diff should carry only the lib test"
RC14="$(gate "$T14")"
[ "$RC14" = 2 ] && ok "lib/**/tests-only diff that moves a Tests column -> blocked (exit 2)" \
  || no "a lib/**/tests-only stale push should block (got $RC14)"

# 15. same for a non-test-named script under tests/ (the generator globs tests/*.sh)
T15="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T15="$T15/kit"; mkkit "$T15"
git -C "$T15" switch -qc feat/frg-helper
printf '#!/usr/bin/env bash\necho demo-agent\n' > "$T15/tests/helper.sh"
git -C "$T15" add -A; git -C "$T15" commit -qm "a tests/ helper naming a feature"
RC15="$(gate "$T15")"
[ "$RC15" = 2 ] && ok "tests/*.sh helper that moves a Tests column -> blocked (exit 2)" \
  || no "a tests/ helper stale push should block (got $RC15)"

# 16. the gate's trigger set is the generator's own: input-pattern prints one ERE
PAT16="$(bash "$KIT/$REG" input-pattern)"
printf 'lib/x/tests/test_a.py\n' | grep -qE "$PAT16" && ! printf 'README.md\n' | grep -qE "$PAT16" \
  && ok "input-pattern matches a lib test and rejects a non-input" || no "input-pattern should match lib tests only"

# --- the codex trust-pin arm ------------------------------------------------

# A fixture whose hooks/codex-hooks.json pins hooks/demo-hook.sh the way the real manifest does.
mkpinned() { # $1=dir
  mkkit "$1"
  local h; h="$(shasum -a 256 "$1/hooks/demo-hook.sh" | awk '{print $1}')"
  printf '{"hooks":{"PreToolUse":[{"hooks":[{"command":"hash_file \\"${PLUGIN_ROOT}/hooks/demo-hook.sh\\" | /usr/bin/grep -q '"'"'^%s '"'"' || exit 2"}]}]}}\n' "$h" > "$1/hooks/codex-hooks.json"
  git -C "$1" add -A; git -C "$1" commit -qm "chore: pin the demo hook"
}

# 17. a hook script edited without a repin -> BLOCKED, and the refusal names the stale file
T17="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T17="$T17/kit"; mkpinned "$T17"
git -C "$T17" switch -qc feat/pin-stale
printf '# edited\n' >> "$T17/hooks/demo-hook.sh"
git -C "$T17" add -A; git -C "$T17" commit -qm "fix: edit a pinned hook"
ERR17="$(mktemp "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
RC17="$(gate "$T17" "$ERR17")"
[ "$RC17" = 2 ] && grep -q 'stale pin: hooks/demo-hook.sh' "$ERR17" \
  && ok "hook edited without a repin -> blocked, names the stale pin (exit 2)" \
  || no "a stale pin should block with the stale pin line (got $RC17)"

# 18. the same branch once repinned -> passes
( cd "$T17" && bash "$KIT/lib/codex/repin.sh" "$T17" >/dev/null )
git -C "$T17" add -A; git -C "$T17" commit -qm "fix: repin the demo hook"
[ "$(gate "$T17")" = 0 ] && ok "hook edited and repinned -> pass (exit 0)" || no "a repinned branch should pass"

# 19. the escape hatch skips the arm on the case-17 shape
T19="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; T19="$T19/kit"; mkpinned "$T19"
git -C "$T19" switch -qc feat/pin-escape
printf '# edited\n' >> "$T19/hooks/demo-hook.sh"
git -C "$T19" add -A; git -C "$T19" commit -qm "fix: edit a pinned hook"
RC19="$( cd "$T19" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
  | CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" DWARVES_KIT_SKIP_CODEX_PIN=1 \
    bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>&1; echo $? )"
[ "$RC19" = 0 ] && ok "DWARVES_KIT_SKIP_CODEX_PIN=1 skips the arm (exit 0)" || no "the escape hatch should skip the arm (got $RC19)"

echo "---"
echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ]
