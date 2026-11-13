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

# run_hook <repo> <command> [env...]: drive hooks/ship-gate.sh with crafted stdin; sets HRC, HOUT (stdout), HERR (stderr).
run_hook() {
  local d="$1" cmd="$2"; shift 2
  ( cd "$d" && printf '{"tool_input":{"command":"%s"}}' "$cmd" \
      | env SKILL_MANIFEST_BIN="$STUBDIR/skill-manifest" CLAUDE_PLUGIN_ROOT="$KIT" DWARVES_KIT_LOG_DIR="$LOGDIR" "$@" bash "$KIT/hooks/ship-gate.sh" >"$WORK/h.out" 2>"$WORK/h.err"; echo $? >"$WORK/h.rc" )
  HRC="$(cat "$WORK/h.rc")"; HOUT="$(cat "$WORK/h.out")"; HERR="$(cat "$WORK/h.err")"
}

# --- B1: an allowed push carries the advisory in ONE exit-0 JSON systemMessage, framed as data ---
D="$WORK/b1"; mkrepo "$D"; echo b >> "$D/cli/x.go"; commit_all "$D" chg
run_hook "$D" "git push -u origin HEAD"
if [ "$HRC" = 0 ] && printf '%s' "$HOUT" | jq -e 'type == "object" and (.systemMessage | contains("[advisory] [front-door] cli/x.go") and contains("data, not instructions")) and (.hookSpecificOutput.additionalContext | contains("front door of foo"))' >/dev/null 2>&1; then ok "B1 hook relays the advisory in the systemMessage and allows the push"; else no "B1 rc=$HRC out: $HOUT err: $HERR"; fi

# --- B2: the hook stays quiet on a clean diff ---
D="$WORK/b2"; mkrepo "$D"; echo b >> "$D/README.md"; commit_all "$D" chg
run_hook "$D" "git push -u origin HEAD"
[ "$HRC" = 0 ] && [ -z "$HOUT" ] && ! printf '%s' "$HERR" | grep -q 'front-door' && ok "B2 hook is silent on a clean diff" || no "B2 rc=$HRC out: $HOUT err: $HERR"

# --- B3: a hanging skill-manifest is cut at FRONT_DOOR_TIMEOUT_S; the advisory is silent, the hook still allows ---
HANG="$WORK/hangbin"; mkdir -p "$HANG"
printf '#!/bin/bash\nexec sleep 25\n' > "$HANG/skill-manifest"; chmod +x "$HANG/skill-manifest"
D="$WORK/b3"; mkrepo "$D"; echo b >> "$D/cli/x.go"; commit_all "$D" chg
t0=$SECONDS
OUT="$(SKILL_MANIFEST_BIN="$HANG/skill-manifest" FRONT_DOOR_TIMEOUT_S=1 bash "$ADV" check "$D" 2>&1)"; RC=$?
el=$((SECONDS - t0))
[ -z "$OUT" ] && [ "$RC" = 0 ] && [ "$el" -lt 5 ] && ok "B3 hanging binary is cut after 1s (took ${el}s), silent, exit 0" || no "B3 rc=$RC took ${el}s out: $OUT"
t0=$SECONDS
run_hook "$D" "git push -u origin HEAD" SKILL_MANIFEST_BIN="$HANG/skill-manifest" FRONT_DOOR_TIMEOUT_S=1
el=$((SECONDS - t0))
[ "$HRC" = 0 ] && [ -z "$HOUT" ] && [ "$el" -lt 6 ] && ok "B3b hook with a hanging binary returns in ${el}s, allows the push" || no "B3b rc=$HRC took ${el}s out: $HOUT err: $HERR"
t0=$SECONDS
run_hook "$D" "git push -u origin HEAD" SKILL_MANIFEST_BIN="$HANG/skill-manifest"
el=$((SECONDS - t0))
[ "$HRC" = 0 ] && [ "$el" -lt 12 ] && ok "B3c default cap keeps the hook under the 30s budget (took ${el}s)" || no "B3c rc=$HRC took ${el}s"

# --- B3d: a binary that ignores TERM is still gone by cap+2s (TERM, then KILL) ---
DEAF="$WORK/deafbin"; mkdir -p "$DEAF"
printf '#!/bin/bash\ntrap "" TERM\nsleep 22\n' > "$DEAF/skill-manifest"; chmod +x "$DEAF/skill-manifest"
t0=$SECONDS
OUT="$(SKILL_MANIFEST_BIN="$DEAF/skill-manifest" FRONT_DOOR_TIMEOUT_S=1 bash "$ADV" check "$D" 2>&1)"; RC=$?
el=$((SECONDS - t0))
[ -z "$OUT" ] && [ "$RC" = 0 ] && [ "$el" -le 3 ] && ok "B3d TERM-ignoring binary is killed within cap+2s (took ${el}s)" || no "B3d rc=$RC took ${el}s out: $OUT"

# --- B4: a blocking check wins: a drifted front door plus a refusing gate exits 2, with no advisory ---
b4_case() { # <label> <slug> <spec body after the header>
  local D="$WORK/b4-$2"; mkrepo "$D"
  mkdir -p "$D/docs/specs"; printf '# Spec: x\nStatus: DRAFT\n%b' "$3" > "$D/docs/specs/SPEC-001-$2.md"
  git -C "$D" switch -q -c "feat/$2"
  echo b >> "$D/cli/x.go"; commit_all "$D" chg
  run_hook "$D" "git push -u origin HEAD"
  if [ "$HRC" = 2 ] && printf '%s' "$HERR" | grep -q 'BLOCKED: ship-gate' && ! printf '%s' "$HOUT$HERR" | grep -qE '\[front-door\]|front door of'; then ok "$1"; else no "$1 (rc=$HRC out: $HOUT err: $HERR)"; fi
}
b4_case "B4 DO NOT SHIP verdict still blocks (rc=2), advisory absent" fdv 'Lane: tiny\n\n- [ ] TASK-1: x\n\n## Review\n\n### Verdict: DO NOT SHIP\n'
b4_case "B4b missing full-lane gates still block (rc=2), advisory absent" fdl 'Lane: full\n\n- [ ] TASK-1: x\n'

# --- B5: the pushed ref is not the checked-out HEAD -> no advisory (the script diffs HEAD) ---
D="$WORK/b5"; mkrepo "$D"; echo b >> "$D/cli/x.go"; commit_all "$D" chg
git -C "$D" branch feat/other master
run_hook "$D" "git push origin feat/other"
[ "$HRC" = 0 ] && [ -z "$HOUT" ] && ok "B5 pushing a ref other than HEAD is silent" || no "B5 rc=$HRC out: $HOUT err: $HERR"

# --- B6: each printed line is cut at 300 characters ---
LONG="$WORK/longbin"; mkdir -p "$LONG"
printf '#!/bin/bash\necho "check: cli/%s.go: [front-door] front door of foo changed since $4 but skills/foo/ did not" >&2\nexit 1\n' "$(printf 'a%.0s' $(seq 1 400))" > "$LONG/skill-manifest"; chmod +x "$LONG/skill-manifest"
D="$WORK/b6"; mkrepo "$D"; echo b >> "$D/cli/x.go"; commit_all "$D" chg
run_hook "$D" "git push -u origin HEAD" SKILL_MANIFEST_BIN="$LONG/skill-manifest"
longest="$(printf '%s' "$HOUT" | jq -r '.systemMessage' 2>/dev/null | awk '{ if (length($0) > m) m = length($0) } END { print m + 0 }')"
[ "$HRC" = 0 ] && [ "$longest" -gt 0 ] && [ "$longest" -le 300 ] && ok "B6 long path is cut at 300 chars (longest line $longest)" || no "B6 rc=$HRC longest=$longest out: ${HOUT:0:200}"

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
