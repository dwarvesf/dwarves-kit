#!/usr/bin/env bash
# test-front-door-advisory.sh -- the ADVISORY skill front-door gate (lib/gate/front-door-advisory.sh).
# Proves: a diff that changes a skill's front_door path without the skill folder WARNS (names the path
# and the skill); a clean diff, a diff that updates the skill too, a missing binary, and a repo with no
# front_door skill stay SILENT; only the front-door diff class is surfaced; every path exits 0; the
# ship-gate hook relays the warning on stderr and still allows the push.
# The skill-manifest binary is a stub that follows the contract (docs/contract.md "Front-door diff rule"
# and the `check: <path>: [<class>] <msg>` stderr line); an optional case runs the real binary.
set -uo pipefail
KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ADV="$KIT/lib/gate/front-door-advisory.sh"
export KIT_CONFIG_OPERATOR="$KIT/tests/fixtures/gates-on"
PASS=0; FAIL=0
ok() { PASS=$((PASS + 1)); echo "ok - $1"; }
no() { FAIL=$((FAIL + 1)); echo "NOT ok - $1"; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1
trap 'rm -rf "$WORK" 2>/dev/null || true' EXIT
LOGDIR="$WORK/log"; mkdir -p "$LOGDIR"

# stub skill-manifest: `check <root> --base <ref>`. Fails the front-door diff rule when anything under
# cli/ changed since <ref> and nothing under skills/foo/ did. STUB_EXTRA=1 adds problem lines of other classes.
STUBDIR="$WORK/stubbin"; mkdir -p "$STUBDIR"
cat > "$STUBDIR/skill-manifest" <<'EOF'
#!/bin/bash
root="$2"; base="$4"
changed="$(git -C "$root" diff --name-only "$base"...HEAD; git -C "$root" diff --name-only HEAD)"
bad=0
if [ "${STUB_EXTRA:-}" = 1 ]; then
  echo "check: skills/foo/SKILL.md: [leak:operator-name] line 3 names the operator" >&2
  echo "check: cli/gone.go: [front-door] metadata.front_door \"cli/gone.go\" matches no path under the target folder" >&2
  bad=1
fi
if printf '%s\n' "$changed" | grep -q '^cli/' && ! printf '%s\n' "$changed" | grep -q '^skills/foo/'; then
  printf '%s\n' "$changed" | grep '^cli/' | while read -r p; do
    echo "check: $p: [front-door] front door of foo changed since $base but skills/foo/ did not" >&2
  done
  bad=1
fi
[ "$bad" = 1 ] && { echo "check: FAILED" >&2; exit 1; }
echo "check: ok, 1 skills (public 1, internal 0, operator 0)"
EOF
chmod +x "$STUBDIR/skill-manifest"

# mkrepo <dir> [front_door-line]: master with skills/foo + cli/, then branch feat/fd checked out.
mkrepo() {
  local d="$1" fd="${2-  front_door: cli/}"
  git init -q -b master "$d"
  git -C "$d" config user.email t@t; git -C "$d" config user.name t
  mkdir -p "$d/skills/foo" "$d/cli"
  printf -- '---\nname: foo\ndescription: Foo skill.\nmetadata:\n  audience: public\n%s\n---\nbody\n' "$fd" > "$d/skills/foo/SKILL.md"
  echo a > "$d/cli/x.go"; echo r > "$d/README.md"
  git -C "$d" add -A; git -C "$d" commit -qm base
  git -C "$d" switch -qc feat/fd
}
commit_all() { git -C "$1" add -A; git -C "$1" commit -qm "$2"; }
adv() { # <repo> -> stdout of the advisory with the stub on PATH; sets RC
  OUT="$(SKILL_MANIFEST_BIN="$STUBDIR/skill-manifest" bash "$ADV" check "$1" 2>&1)"; RC=$?
}

# --- A1: a front-door path changed without its skill WARNS, naming the path and the skill ---
D="$WORK/a1"; mkrepo "$D"; echo b >> "$D/cli/x.go"; commit_all "$D" chg
adv "$D"
if printf '%s' "$OUT" | grep -q '^\[front-door\] cli/x.go' && printf '%s' "$OUT" | grep -q 'front door of foo'; then ok "A1 drifted front door warns, names cli/x.go and skill foo"; else no "A1 expected a front-door warning, got: $OUT"; fi
[ "$RC" = 0 ] && ok "A1 advisory exits 0" || no "A1 exit $RC"

# --- A2: the skill folder changed too -> silent ---
D="$WORK/a2"; mkrepo "$D"; echo b >> "$D/cli/x.go"; echo more >> "$D/skills/foo/SKILL.md"; commit_all "$D" chg
adv "$D"
[ -z "$OUT" ] && ok "A2 front door + skill updated together is silent" || no "A2 expected silence, got: $OUT"

# --- A3: a clean diff (no front-door path) -> silent ---
D="$WORK/a3"; mkrepo "$D"; echo b >> "$D/README.md"; commit_all "$D" chg
adv "$D"
[ -z "$OUT" ] && [ "$RC" = 0 ] && ok "A3 clean diff is silent" || no "A3 expected silence, got rc=$RC: $OUT"

# --- A4: binary absent -> silent, exit 0 (env var points nowhere; and not on PATH) ---
D="$WORK/a4"; mkrepo "$D"; echo b >> "$D/cli/x.go"; commit_all "$D" chg
OUT="$(SKILL_MANIFEST_BIN="$WORK/nope/skill-manifest" bash "$ADV" check "$D" 2>&1)"; RC=$?
[ -z "$OUT" ] && [ "$RC" = 0 ] && ok "A4 SKILL_MANIFEST_BIN missing is silent" || no "A4 expected silence, got rc=$RC: $OUT"
OUT="$(env -u SKILL_MANIFEST_BIN PATH="/usr/bin:/bin" bash "$ADV" check "$D" 2>&1)"; RC=$?
if command -v skill-manifest >/dev/null 2>&1 && PATH="/usr/bin:/bin" command -v skill-manifest >/dev/null 2>&1; then
  echo "skip - A4b skill-manifest lives in /usr/bin here"
else
  [ -z "$OUT" ] && [ "$RC" = 0 ] && ok "A4b no binary on PATH is silent" || no "A4b expected silence, got rc=$RC: $OUT"
fi

# --- A5: PATH lookup works when SKILL_MANIFEST_BIN is unset ---
OUT="$(env -u SKILL_MANIFEST_BIN PATH="$STUBDIR:/usr/bin:/bin" bash "$ADV" check "$D" 2>&1)"; RC=$?
printf '%s' "$OUT" | grep -q '^\[front-door\] cli/x.go' && ok "A5 binary found on PATH" || no "A5 expected a warning via PATH, got: $OUT"

# --- A6: no skills dir, or skills without front_door -> silent even with the binary present ---
D="$WORK/a6"; git init -q -b master "$D"; git -C "$D" config user.email t@t; git -C "$D" config user.name t
mkdir -p "$D/cli"; echo a > "$D/cli/x.go"; commit_all "$D" base; git -C "$D" switch -qc feat/fd; echo b >> "$D/cli/x.go"; commit_all "$D" chg
adv "$D"
[ -z "$OUT" ] && ok "A6 repo with no skills is silent" || no "A6 expected silence, got: $OUT"
D="$WORK/a6b"; mkrepo "$D" "  note: none"; echo b >> "$D/cli/x.go"; commit_all "$D" chg
adv "$D"
[ -z "$OUT" ] && ok "A6b skills without front_door are silent" || no "A6b expected silence, got: $OUT"

# --- A7: only the front-door diff class is surfaced (leak and no-such-path problems are ignored) ---
D="$WORK/a7"; mkrepo "$D"; echo b >> "$D/README.md"; commit_all "$D" chg
OUT="$(STUB_EXTRA=1 SKILL_MANIFEST_BIN="$STUBDIR/skill-manifest" bash "$ADV" check "$D" 2>&1)"; RC=$?
[ -z "$OUT" ] && [ "$RC" = 0 ] && ok "A7 other problem classes are not surfaced" || no "A7 expected silence, got rc=$RC: $OUT"
echo b >> "$D/cli/x.go"; commit_all "$D" chg2
OUT="$(STUB_EXTRA=1 SKILL_MANIFEST_BIN="$STUBDIR/skill-manifest" bash "$ADV" check "$D" 2>&1)"
n="$(printf '%s\n' "$OUT" | grep -c '^\[front-door\]')"
if [ "$n" = 1 ] && ! printf '%s' "$OUT" | grep -q 'leak\|matches no path'; then ok "A7b only the drift line is printed beside other classes"; else no "A7b expected 1 drift line, got: $OUT"; fi

# --- B1: the ship-gate hook relays the warning and still allows the push ---
D="$WORK/b1"; mkrepo "$D"; echo b >> "$D/cli/x.go"; commit_all "$D" chg
ERR="$WORK/b1.err"
( cd "$D" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
    | SKILL_MANIFEST_BIN="$STUBDIR/skill-manifest" CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"$ERR"; echo $? > "$WORK/b1.rc" )
if [ "$(cat "$WORK/b1.rc")" = 0 ] && grep -q '^\[advisory\] \[front-door\] cli/x.go' "$ERR"; then ok "B1 hook prints the advisory and allows the push"; else no "B1 rc=$(cat "$WORK/b1.rc") stderr: $(tr '\n' ' ' < "$ERR")"; fi

# --- B2: the hook stays quiet on a clean diff ---
D="$WORK/b2"; mkrepo "$D"; echo b >> "$D/README.md"; commit_all "$D" chg
ERR="$WORK/b2.err"
( cd "$D" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
    | SKILL_MANIFEST_BIN="$STUBDIR/skill-manifest" CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" bash "$KIT/hooks/ship-gate.sh" >/dev/null 2>"$ERR"; echo $? > "$WORK/b2.rc" )
if [ "$(cat "$WORK/b2.rc")" = 0 ] && ! grep -q 'front-door' "$ERR"; then ok "B2 hook is silent on a clean diff"; else no "B2 rc=$(cat "$WORK/b2.rc") stderr: $(tr '\n' ' ' < "$ERR")"; fi

# --- C1: the real skill-manifest, when one is given or installed ---
REAL="${REAL_SKILL_MANIFEST:-$(command -v skill-manifest 2>/dev/null || true)}"
if [ -n "$REAL" ] && [ -x "$REAL" ]; then
  D="$WORK/c1"; mkrepo "$D"; echo b >> "$D/cli/x.go"; commit_all "$D" chg
  OUT="$(SKILL_MANIFEST_BIN="$REAL" bash "$ADV" check "$D" 2>&1)"
  printf '%s' "$OUT" | grep -q '^\[front-door\] cli/x.go' && ok "C1 real skill-manifest drift is warned" || no "C1 real binary: $OUT"
  echo more >> "$D/skills/foo/SKILL.md"; commit_all "$D" fix
  OUT="$(SKILL_MANIFEST_BIN="$REAL" bash "$ADV" check "$D" 2>&1)"
  [ -z "$OUT" ] && ok "C1b real skill-manifest is silent once the skill moved" || no "C1b real binary: $OUT"
else
  echo "skip - C1 no real skill-manifest (set REAL_SKILL_MANIFEST=<path> to run it)"
fi

echo "---"; echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
