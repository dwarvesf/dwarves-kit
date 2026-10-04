#!/usr/bin/env bash
# test-spec-find.sh -- lib/spec/spec-find.sh (spec_files, spec_for_slug) and its five callers:
# spec-next.sh, gate-ledger.sh validate-round open, hooks/ship-gate.sh, proof-ledger.sh
# _negctl_required, pitch.sh _find_spec. Co-located specs (<ns>/docs/specs/SPEC-*.md) must be
# found; a root-only repo must behave as before.
#
# Negative control in-suite: a mutant kit copy whose spec_files is root-only. Every caller case
# that finds a co-located spec must flip under it, and a root-spec positive control in the same
# mutant kit proves the mutant callers really ran the spec path.
#
# Isolation: fresh HOME, no inherited git env, mktemp repos, a fresh DWARVES_KIT_LOG_DIR per
# case, a per-case reservation file, SPEC_NEXT_NO_PR_SCAN=1.
#
# Run: bash tests/test-spec-find.sh     Exit 0 = all pass.
set -uo pipefail
unset $(git rev-parse --local-env-vars)
SF_HOME="$(mktemp -d)"; HOME="$SF_HOME"; export HOME
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export SPEC_NEXT_NO_PR_SCAN=1
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
export KIT_CONFIG_OPERATOR="$KIT_DIR/tests/fixtures/gates-on"   # quality gates are opt-in; this suite exercises them ON

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in: $2)" ;; esac; }

TMP="$(cd "$(mktemp -d)" && pwd -P)"
cleanup() { chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP" "$SF_HOME"; }
trap cleanup EXIT
fresh() { mktemp -d "$TMP/x.XXXXXX"; }   # mktemp, not a counter: callers run it in subshells
spec() { mkdir -p "$(dirname "$1")"; printf '# Spec\n\nStatus: DRAFT\n%s\n' "${2:-}" > "$1"; }

# git repo: master holds the marker (+ an optional root spec), then a work branch.
# $1 dir, $2 branch ("" = stay on master)
mkrepo() {
  git init -q -b master "$1"
  git -C "$1" config user.email t@t; git -C "$1" config user.name t; git -C "$1" config commit.gpgsign false
  mkdir -p "$1/docs/verification"; echo marker > "$1/docs/verification/README.md"
}
commit() { git -C "$1" add -A; git -C "$1" commit -qm "${2:-c}"; }

# ----- resolver: sourced in this shell ------------------------------------------------------
# shellcheck source=lib/spec/spec-find.sh
source "$KIT_DIR/lib/spec/spec-find.sh"

echo "== resolver =="
# Row 1: pick order + path form
R="$TMP/r1"; mkdir -p "$R"
spec "$R/docs/specs/SPEC-002-b.md"; spec "$R/docs/specs/SPEC-001-a.md"
spec "$R/tools/x/docs/specs/SPEC-147-cs.md"; spec "$R/a/docs/specs/SPEC-010-z.md"
spec "$R/tools/a/docs/specs/SPEC-003-q.md"; spec "$R/tools/Z/docs/specs/SPEC-004-r.md"
WANT="$R/docs/specs/SPEC-001-a.md
$R/docs/specs/SPEC-002-b.md
$R/a/docs/specs/SPEC-010-z.md
$R/tools/Z/docs/specs/SPEC-004-r.md
$R/tools/a/docs/specs/SPEC-003-q.md
$R/tools/x/docs/specs/SPEC-147-cs.md"
eq "row1 spec_files: root ls order, then depth, then C order (Z before a)" "$(spec_files "$R")" "$WANT"
case "$(spec_files "$R")" in *"/./"*) bad "row1 no './' in any path" ;; *) ok "row1 no './' in any path" ;; esac

# Row 2: prunes and depth cap
R="$TMP/r2"; mkdir -p "$R"
spec "$R/a/b/c/d/docs/specs/SPEC-020-deep4.md"
for p in a/b/c/d/e .hidden .claude/worktrees/w node_modules/p vendor/p build/p target/p dist/p; do
  spec "$R/$p/docs/specs/SPEC-099-pruned.md"
done
spec "$R/x/specs/SPEC-098-notdocs.md"; spec "$R/x/docs/specs/sub/SPEC-097-sub.md"
mkdir -p "$R/y/docs/specs/SPEC-096-dir.md"
spec "$R/nl"$'\n'"x/docs/specs/SPEC-095-nl.md"
eq "row2 depth-4 namespace kept; depth-5, dot-dirs, node_modules, vendor, build, target, dist, non-docs/specs, dirs, newline paths dropped" \
  "$(spec_files "$R")" "$R/a/b/c/d/docs/specs/SPEC-020-deep4.md"

# Row 3: decoy (Edge Case 9) and the root-glob invariant
R="$TMP/r3"; mkdir -p "$R"; spec "$R/tools/y/docs/specs/SPEC-147-foo-cs.md"
eq "row3 decoy SPEC-147-foo-cs.md is not slug cs" "$(spec_for_slug "$R" cs)" ""
eq "row3 the decoy is slug foo-cs" "$(spec_for_slug "$R" foo-cs)" "$R/tools/y/docs/specs/SPEC-147-foo-cs.md"
spec "$R/docs/specs/SPEC-001-foo-cs.md"
eq "row3 root keeps the glob (equals ls | head -1)" "$(spec_for_slug "$R" cs)" "$(ls "$R"/docs/specs/SPEC-*-cs.md | head -1)"

# Row 4: root wins over co-located (Edge Case 1)
R="$TMP/r4"; mkdir -p "$R"
spec "$R/a/docs/specs/SPEC-001-s.md"; spec "$R/docs/specs/SPEC-900-s.md"
eq "row4 root wins a shared slug" "$(spec_for_slug "$R" s)" "$R/docs/specs/SPEC-900-s.md"

# Row 5: depth then C order (Edge Cases 2, 3)
R="$TMP/r5"; mkdir -p "$R"
spec "$R/a/b/docs/specs/SPEC-001-s.md"; spec "$R/z/docs/specs/SPEC-002-s.md"
spec "$R/tools/b/docs/specs/SPEC-001-t.md"; spec "$R/tools/a/docs/specs/SPEC-009-t.md"
spec "$R/tools/a/docs/specs/SPEC-001-u.md"; spec "$R/tools/Z/docs/specs/SPEC-009-u.md"
eq "row5 shallower wins" "$(spec_for_slug "$R" s)" "$R/z/docs/specs/SPEC-002-s.md"
eq "row5 same depth: C-smaller path wins" "$(spec_for_slug "$R" t)" "$R/tools/a/docs/specs/SPEC-009-t.md"
eq "row5 same depth: C order puts Z before a" "$(spec_for_slug "$R" u)" "$R/tools/Z/docs/specs/SPEC-009-u.md"

# Row 6: spaces; a root inside .claude/worktrees (Edge Cases 6, 7)
R="$TMP/r 6 root"; mkdir -p "$R"; spec "$R/my tools/x/docs/specs/SPEC-030-sp.md"
eq "row6 space in root and in namespace" "$(spec_for_slug "$R" sp)" "$R/my tools/x/docs/specs/SPEC-030-sp.md"
R="$TMP/r6/.claude/worktrees/x"; mkdir -p "$R"; spec "$R/tools/q/docs/specs/SPEC-031-wt.md"
eq "row6 root inside .claude/worktrees is not pruned" "$(spec_for_slug "$R" wt)" "$R/tools/q/docs/specs/SPEC-031-wt.md"

# Row 7: unreadable subdirectory; exit 0 always
R="$TMP/r7"; mkdir -p "$R"; spec "$R/ok/docs/specs/SPEC-040-ok.md"
spec_files /nonexistent/sf >/dev/null; eq "row7 spec_files on a missing root exits 0" "$?" 0
spec_for_slug "$R" ""; eq "row7 spec_for_slug empty slug exits 0" "$?" 0
spec_for_slug "$R" nomatch; eq "row7 spec_for_slug no match exits 0" "$?" 0
if [ "$(id -u)" = 0 ]; then
  echo "SKIP row7 unreadable dir (running as root)"
else
  spec "$R/locked/docs/specs/SPEC-041-lk.md"; chmod 000 "$R/locked"
  OUT="$(spec_files "$R")"; RC=$?
  chmod 755 "$R/locked"
  eq "row7 unreadable dir: exit 0" "$RC" 0
  eq "row7 unreadable dir: other specs still listed" "$OUT" "$R/ok/docs/specs/SPEC-040-ok.md"
fi

# ----- caller fixtures -------------------------------------------------------------------
# CS: root SPEC-005 on master; feat/cs adds only tools/x/docs/specs/SPEC-147-cs.md (Lane: full).
CS="$TMP/cs"; mkrepo "$CS"; spec "$CS/docs/specs/SPEC-005-old.md" 'Lane: full'; commit "$CS" init
git -C "$CS" switch -qc feat/cs; spec "$CS/tools/x/docs/specs/SPEC-147-cs.md" 'Lane: full'; commit "$CS" "add spec"
CSPEC="$CS/tools/x/docs/specs/SPEC-147-cs.md"
# RS: root-only control, feat/rs with docs/specs/SPEC-001-rs.md (Lane: full).
RS="$TMP/rs"; mkrepo "$RS"; commit "$RS" init
git -C "$RS" switch -qc feat/rs; spec "$RS/docs/specs/SPEC-001-rs.md" 'Lane: full'; commit "$RS" "add spec"
# NC: negative-control fixture. Base holds a co-located Lane: full spec for slug nc; the
# working change is a small behavioral edit with a green-run-only proof.
nc_fixture() {  # $1 dir, $2 spec path (rel) or ""
  mkrepo "$1"; mkdir -p "$1/lib"; echo base > "$1/lib/thing.sh"
  [ -z "$2" ] || spec "$1/$2" 'Lane: full'
  commit "$1" base
  echo changed >> "$1/lib/thing.sh"
  printf '## green run\nCommand: `bash test.sh`\nExit: 0\nOutput: test: all 1 passed\nVerdict: PASS\n' > "$1/docs/verification/nc.md"
  git -C "$1" add -A
}
NC_CO="$TMP/nc-co";     nc_fixture "$NC_CO" tools/x/docs/specs/SPEC-147-nc.md
NC_ROOT="$TMP/nc-root"; nc_fixture "$NC_ROOT" docs/specs/SPEC-001-nc.md
NC_NONE="$TMP/nc-none"; nc_fixture "$NC_NONE" ""
NCO="$TMP/nc-operator"; mkdir -p "$NCO"
cp "$KIT_DIR/tests/fixtures/gates-on/kit.toml" "$NCO/kit.toml"; printf '\n[gate]\nnegative_control = "full"\n' >> "$NCO/kit.toml"

# Caller drivers. $K = the kit under test.
sn()    { ( cd "$1" && env DWARVES_KIT_LOG_DIR="$(fresh)" SPEC_RESERVE_FILE="$(fresh)/res.log" bash "$K/lib/spec/spec-next.sh" "${@:2}" 2>/dev/null ); }
vr()    { ( cd "$1" && env DWARVES_KIT_LOG_DIR="$(fresh)" bash "$K/lib/gate/gate-ledger.sh" validate-round open "$2" "$3" 2>&1 ); }
gate()  { ( cd "$1" && printf '{"tool_input":{"command":"git push -u origin HEAD"}}' \
            | CLAUDE_PLUGIN_ROOT="$K" DWARVES_KIT_LOG_DIR="$(fresh)" bash "$K/hooks/ship-gate.sh" 2>&1 >/dev/null ); }
negctl(){ ( cd "$1" && env KIT_CONFIG_OPERATOR="$NCO" DWARVES_KIT_LOG_DIR="$(fresh)" bash "$K/lib/gate/proof-ledger.sh" check "$1" "$(git -C "$1" rev-parse HEAD)" nc >/dev/null 2>&1 ); }
pitch() { ( cd "$1" && env DWARVES_KIT_LOG_DIR="$(fresh)" bash "$K/lib/pitch.sh" ask "$2" 2>/dev/null ); }

K="$KIT_DIR"
echo "== callers (real kit) =="
# Row 8: spec-next
eq "row8 next counts co-located SPEC-147" "$(sn "$CS" next)" 148
RES="$(fresh)/res.log"; LD="$(fresh)"
A="$(cd "$CS" && DWARVES_KIT_LOG_DIR="$LD" SPEC_RESERVE_FILE="$RES" bash "$K/lib/spec/spec-next.sh" reserve 2>/dev/null)"
B="$(cd "$CS" && DWARVES_KIT_LOG_DIR="$LD" SPEC_RESERVE_FILE="$RES" bash "$K/lib/spec/spec-next.sh" reserve 2>/dev/null)"
eq "row8 reserve twice (one state file): 148 then 149" "$A $B" "148 149"
sn "$CS" check 147 >/dev/null; eq "row8 check 147 reports taken" "$?" 1
E8="$TMP/ec8"; mkrepo "$E8"; spec "$E8/docs/specs/SPEC-005-x.md"; spec "$E8/tools/a/docs/specs/SPEC-001-a.md"; commit "$E8" init
sn "$E8" check 001 >/dev/null; eq "EC8 co-located SPEC-001: check 001 reports taken" "$?" 1
eq "EC8 low co-located number leaves next alone" "$(sn "$E8" next)" 006
E5="$TMP/ec5"; mkrepo "$E5"; spec "$E5/docs/specs/SPEC-005-x.md"; commit "$E5" init
git -C "$E5" worktree add -q "$E5/.claude/worktrees/w" -b feat/w
spec "$E5/.claude/worktrees/w/tools/q/docs/specs/SPEC-200-w.md"
eq "EC5 sibling worktree's co-located SPEC-200 counted via the worktree loop" "$(sn "$E5" next)" 201
eq "EC5 main checkout walk never picks .claude/worktrees" "$(spec_for_slug "$E5" w)" ""

# Row 9: validate-round open
OUT="$(vr "$CS" cs "$CSPEC")"; RC=$?
eq "row9 validate-round open on a co-located spec exits 0" "$RC" 0
case "$OUT" in [0-9a-f]*.*.1) ok "row9 token printed" ;; *) bad "row9 token printed (got '$OUT')" ;; esac
E1="$TMP/ec1"; mkrepo "$E1"; commit "$E1" init
git -C "$E1" switch -qc feat/cs; spec "$E1/docs/specs/SPEC-005-cs.md"; spec "$E1/tools/x/docs/specs/SPEC-147-cs.md" 'Lane: full'; commit "$E1" spec
OUT="$(vr "$E1" cs "$E1/tools/x/docs/specs/SPEC-147-cs.md")"; RC=$?
eq "EC1 validate-round open on the co-located twin refuses" "$RC" 1
has "EC1 refusal names the ship-gate pick" "$OUT" "is not the ship-gate pick '$E1/docs/specs/SPEC-005-cs.md'"
vr "$RS" rs "$RS/docs/specs/SPEC-001-rs.md" >/dev/null; eq "row14 validate-round open on a root spec still exits 0" "$?" 0

# Row 10: ship-gate
OUT="$(gate "$CS")"; RC=$?
eq "row10 ship-gate: co-located Lane: full, empty ledger exits 2" "$RC" 2
has "row10 ship-gate names the full lane" "$OUT" "The 'full' lane requires gates"
OUT="$(gate "$E1")"; RC=$?
eq "EC1 ship-gate reads the root spec (no Lane header) over the co-located full one" "$RC" 2
has "EC1 ship-gate blocks on the root spec's missing lane" "$OUT" "has no 'Lane:' header"
E9="$TMP/ec9"; mkrepo "$E9"; commit "$E9" init
git -C "$E9" switch -qc feat/cs; spec "$E9/tools/y/docs/specs/SPEC-147-foo-cs.md" 'Lane: full'; commit "$E9" spec
gate "$E9" >/dev/null; eq "EC9 ship-gate: only the decoy present exits 0" "$?" 0
OUT="$(gate "$RS")"; RC=$?
eq "row14 ship-gate: root Lane: full still exits 2" "$RC" 2

# Row 11: ship-gate on a stale install (no spec-find.sh; old libs that never sourced it)
STALE="$TMP/stale-kit"; mkdir -p "$STALE"
cp -R "$KIT_DIR/lib" "$KIT_DIR/hooks" "$KIT_DIR/kit.toml" "$KIT_DIR/VERSION" "$STALE/"
rm "$STALE/lib/spec/spec-find.sh"
for f in gate/gate-ledger.sh gate/proof-ledger.sh spec/spec-next.sh pitch.sh; do
  sed -i.bak '/spec-find\.sh/d' "$STALE/lib/$f" && rm "$STALE/lib/$f.bak"
done
K="$STALE"
OUT="$(gate "$RS")"; RC=$?
eq "row11 stale install: root full-lane spec still found (exit 2)" "$RC" 2
has "row11 stale install: blocked on the lane, not a FATAL" "$OUT" "The 'full' lane requires gates"
case "$OUT" in *FATAL*) bad "row11 stale install: no FATAL in the gaps" ;; *) ok "row11 stale install: no FATAL in the gaps" ;; esac
gate "$CS" >/dev/null; eq "row11 stale install: fallback is the root glob (co-located only, exit 0)" "$?" 0
K="$KIT_DIR"

# Row 12: _negctl_required and pitch _find_spec
negctl "$NC_CO";   eq "row12 _negctl_required yes for a co-located Lane: full spec (check exits 1)" "$?" 1
negctl "$NC_NONE"; eq "row12 control: no spec, negative control waived (check exits 0)" "$?" 0
eq "row12 pitch finds the co-located spec, no './'" "$(pitch "$CS" cs)" \
  "Review \`tools/x/docs/specs/SPEC-147-cs.md\` and confirm ship-readiness for \`cs\` (no PR reference recorded yet)."
eq "row14 pitch root path prints as docs/specs/..." "$(pitch "$RS" rs)" \
  "Review \`docs/specs/SPEC-001-rs.md\` and confirm ship-readiness for \`rs\` (no PR reference recorded yet)."

# ----- mutant: spec_files root-only -------------------------------------------------------
echo "== mutant: root-only spec_files =="
MUT="$TMP/mutant-kit"; mkdir -p "$MUT"
cp -R "$KIT_DIR/lib" "$KIT_DIR/hooks" "$KIT_DIR/kit.toml" "$KIT_DIR/VERSION" "$MUT/"
printf '\nspec_files() { ls "$1"/docs/specs/SPEC-*.md 2>/dev/null; return 0; }\n' >> "$MUT/lib/spec/spec-find.sh"
eq "mutant in effect: spec_files lists the root spec only" \
  "$( source "$MUT/lib/spec/spec-find.sh"; spec_files "$CS" )" "$CS/docs/specs/SPEC-005-old.md"
K="$MUT"
# Positive controls: the mutant callers still run the spec path for a root spec.
eq "mutant control: spec-next still reads root specs" "$(sn "$RS" next)" 002
vr "$RS" rs "$RS/docs/specs/SPEC-001-rs.md" >/dev/null; eq "mutant control: validate-round opens a root spec" "$?" 0
gate "$RS" >/dev/null; eq "mutant control: ship-gate blocks a root full-lane spec" "$?" 2
negctl "$NC_ROOT"; eq "mutant control: _negctl_required yes for a root full-lane spec" "$?" 1
has "mutant control: pitch finds a root spec" "$(pitch "$RS" rs)" "docs/specs/SPEC-001-rs.md"
# The flips: each co-located caller case must go red.
eq "mutant flip: spec-next next prints 006" "$(sn "$CS" next)" 006
OUT="$(vr "$CS" cs "$CSPEC")"; RC=$?
eq "mutant flip: validate-round open exits 1" "$RC" 1
has "mutant flip: validate-round finds no spec" "$OUT" "no SPEC-*-cs.md under"
gate "$CS" >/dev/null; eq "mutant flip: ship-gate exits 0 (no spec)" "$?" 0
negctl "$NC_CO"; eq "mutant flip: _negctl_required not yes (check exits 0)" "$?" 0
eq "mutant flip: pitch finds no spec" "$(pitch "$CS" cs)" "Confirm ship-readiness for \`cs\` (no spec or PR reference found)."
K="$KIT_DIR"

echo "---"
echo "test-spec-find: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
