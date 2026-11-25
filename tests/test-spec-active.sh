#!/usr/bin/env bash
# test-spec-active.sh -- lib/spec/spec-active.sh: spec_active in default, --live and --set modes, and
# the CLI form. The default mode must equal spec_for_slug on every fixture slug (the ship gate binds
# to that pick); --live must not walk the tree.
#
# Run: bash tests/test-spec-active.sh     Exit 0 = all pass.
set -uo pipefail
unset $(git rev-parse --local-env-vars)
SA_HOME="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; HOME="$SA_HOME"; export HOME
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL+1)); echo "FAIL $1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3' got '$2')"; fi; }

_td="$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX")" || exit 1; TMP="$(cd "$_td" && pwd -P)"
cleanup() { chmod -R u+rwx "$TMP" 2>/dev/null; rm -rf "$TMP" "$SA_HOME"; }
trap cleanup EXIT

TAB=$(printf '\t')
spec() { mkdir -p "$(dirname "$1")"; { printf '# Spec\n\n'; [ -n "$2" ] && printf 'Status: %s\n' "$2"; printf '\n'; } > "$1"; }
fresh() { mktemp -d "$TMP/r.XXXXXX"; }

# shellcheck source=lib/spec/spec-active.sh
. "$KIT_DIR/lib/spec/spec-active.sh"
# run <args...>: stdout, then the exit code on the last line
run() { local out rc=0; out=$(spec_active "$@" 2>/dev/null) || rc=$?; printf '%s\n%s' "$out" "$rc"; }
rc_of() { local rc=0; spec_active "$@" >/dev/null 2>&1 || rc=$?; printf '%s' "$rc"; }

R="$(fresh)"
spec "$R/docs/specs/SPEC-010-alpha.md" SHIPPED
spec "$R/docs/specs/SPEC-020-beta.md" DRAFT
spec "$R/docs/specs/SPEC-030-gamma.md" DRAFT
spec "$R/docs/specs/SPEC-040-gateway.md" DRAFT
spec "$R/tools/x/docs/specs/SPEC-005-delta.md" DRAFT

echo "== default mode: the name pick =="
eq "C1 root spec by name" "$(spec_active --slug beta "$R")" "name${TAB}$R/docs/specs/SPEC-020-beta.md"
eq "C2 co-located spec by name" "$(spec_active --slug delta "$R")" "name${TAB}$R/tools/x/docs/specs/SPEC-005-delta.md"
eq "C3 a SHIPPED spec is still picked" "$(spec_active --slug alpha "$R")" "name${TAB}$R/docs/specs/SPEC-010-alpha.md"
eq "no match: empty, exit 1" "$(run --slug nope "$R")" "
1"
eq "--branch derives the slug as the part after the first slash" "$(spec_active --branch feat/beta "$R")" "name${TAB}$R/docs/specs/SPEC-020-beta.md"
eq "--branch with no slash uses the whole branch" "$(spec_active --branch beta "$R")" "name${TAB}$R/docs/specs/SPEC-020-beta.md"
eq "edge: slug gate does not pick gateway" "$(run --slug gate "$R")" "
1"
eq "edge: an empty slug picks nothing" "$(run --branch "" "$R")" "
1"
eq "default mode needs a slug or a branch" "$(rc_of "$R")" "64"

echo "== AC1: default mode equals spec_for_slug on every fixture slug =="
# shellcheck source=lib/spec/spec-find.sh
. "$KIT_DIR/lib/spec/spec-find.sh"
mkdir -p "$R/tools/y/docs/specs"; spec "$R/tools/y/docs/specs/SPEC-abc-word.md" DRAFT; spec "$R/tools/y/docs/specs/SPEC-007-beta.md" DRAFT
for s in alpha beta gamma gateway delta word nope gate gam "" "a b" 'be*'; do
  eq "AC1 slug '$s'" "$(spec_active --slug "$s" "$R" 2>/dev/null | cut -f2-)" "$(spec_for_slug "$R" "$s")"
done
E="$(fresh)"
eq "AC1 empty repo" "$(spec_active --slug alpha "$E" 2>/dev/null | cut -f2-)" "$(spec_for_slug "$E" alpha)"

echo "== --live =="
L="$(fresh)"; spec "$L/docs/specs/SPEC-050-solo.md" DRAFT
eq "C4 lone open spec, unrelated branch" "$(spec_active --live --branch feat/zzz "$L")" "live${TAB}$L/docs/specs/SPEC-050-solo.md"
eq "C5 several open, branch token matches one" "$(run --live --branch feat/x_gamma "$R")" "branch${TAB}$R/docs/specs/SPEC-030-gamma.md
0"
eq "C5b a name pick that is open wins" "$(spec_active --live --branch feat/beta "$R")" "name${TAB}$R/docs/specs/SPEC-020-beta.md"
eq "a SHIPPED name pick falls through to the open set" "$(run --live --branch feat/alpha "$R" | tail -1)" "2"
eq "C6 several open, no match: every candidate, exit 2" "$(run --live --branch feat/zzz "$R")" "ambiguous${TAB}$R/docs/specs/SPEC-020-beta.md
ambiguous${TAB}$R/docs/specs/SPEC-030-gamma.md
ambiguous${TAB}$R/docs/specs/SPEC-040-gateway.md
2"
eq "edge: token gate matches whole tokens only (not gateway)" "$(run --live --branch feat/gate "$R" | tail -1)" "2"
eq "branch with a dot and underscore splits into tokens" "$(spec_active --live --branch feat/x_gamma.y "$R")" "branch${TAB}$R/docs/specs/SPEC-030-gamma.md"
eq "detached HEAD (empty branch), lone open spec" "$(spec_active --live --branch "" "$L")" "live${TAB}$L/docs/specs/SPEC-050-solo.md"
eq "detached HEAD, several open: ambiguous" "$(run --live --branch "" "$R" | tail -1)" "2"
HL="$(fresh)"; spec "$HL/docs/specs/SPEC-020-beta.md" DRAFT; spec "$HL/docs/specs/SPEC-030-gamma.md" ""
eq "C7 a header-less spec is open" "$(run --live --branch feat/zzz "$HL" | tail -1)" "2"
eq "C7b header-less spec picked by its branch" "$(spec_active --live --branch feat/gamma "$HL")" "name${TAB}$HL/docs/specs/SPEC-030-gamma.md"
CO="$(fresh)"; spec "$CO/tools/x/docs/specs/SPEC-005-delta.md" DRAFT
eq "C8 co-located open spec, none at root: exit 1" "$(run --live --branch feat/delta "$CO")" "
1"
CL="$(fresh)"; spec "$CL/docs/specs/SPEC-010-old.md" SHIPPED; spec "$CL/docs/specs/SPEC-011-older.md" PARKED
eq "no open spec: exit 1" "$(run --live --branch feat/x "$CL")" "
1"

echo "== --set =="
eq "--set lists every open spec at root" "$(spec_active --set "$R")" "live${TAB}$R/docs/specs/SPEC-020-beta.md
live${TAB}$R/docs/specs/SPEC-030-gamma.md
live${TAB}$R/docs/specs/SPEC-040-gateway.md"
eq "--set with none open: exit 1" "$(rc_of --set "$CL")" "1"

echo "== C9 / AC9: --live walks nothing and reads Status: in one pass =="
STUBS="$TMP/stubs"; mkdir -p "$STUBS"
for t in find ls; do printf '#!/bin/sh\necho ran >> "%s/stub-ran"\nexit 99\n' "$TMP" > "$STUBS/$t"; chmod +x "$STUBS/$t"; done
KD="$TMP/kitlib"; mkdir -p "$KD"
cp "$KIT_DIR"/lib/spec/spec-active.sh "$KIT_DIR"/lib/spec/spec-find.sh "$KIT_DIR"/lib/spec/states.tsv "$KD/"
cp "$KIT_DIR/lib/spec/spec-status.sh" "$KD/spec-status-real.sh"
printf '#!/bin/bash\necho "$*" >> "%s/status-calls"\nexec bash "$(dirname "$0")/spec-status-real.sh" "$@"\n' "$TMP" > "$KD/spec-status.sh"
out=$(PATH="$STUBS:$PATH" bash "$KD/spec-active.sh" --live --branch feat/x_gamma "$R" 2>&1); rc=$?
eq "C9 --live answers with find and ls stubbed to fail" "$out" "branch${TAB}$R/docs/specs/SPEC-030-gamma.md"
eq "C9 exit 0" "$rc" "0"
eq "C9 the stubs never ran" "$([ -e "$TMP/stub-ran" ] && echo ran || echo none)" "none"
eq "AC9 one spec-status.sh pass" "$(wc -l < "$TMP/status-calls" | tr -d ' ')" "1"
case "$(cat "$TMP/status-calls")" in live*) ok "AC9 the pass is spec-status.sh live" ;; *) bad "AC9 the pass is spec-status.sh live" ;; esac

echo "== a partial install: spec-find.sh missing =="
PK="$TMP/partial"; mkdir -p "$PK"; cp "$KIT_DIR/lib/spec/spec-active.sh" "$PK/"
src_rc=0; bash -c ". '$PK/spec-active.sh'" >/dev/null 2>&1 || src_rc=$?
eq "sourcing fails, so the caller takes its own fallback" "$src_rc" "1"
cli_rc=0; bash "$PK/spec-active.sh" --slug beta "$R" >/dev/null 2>&1 || cli_rc=$?
eq "the CLI exits 1" "$cli_rc" "1"

echo "== CLI form, and sourcing under set -e / set -u =="
eq "CLI prints the same line" "$(bash "$KIT_DIR/lib/spec/spec-active.sh" --live --branch feat/x_gamma "$R")" "branch${TAB}$R/docs/specs/SPEC-030-gamma.md"
cli_rc=0; bash "$KIT_DIR/lib/spec/spec-active.sh" --live --branch feat/zzz "$R" >/dev/null 2>&1 || cli_rc=$?
eq "CLI exits 2 on ambiguity" "$cli_rc" "2"
cli_rc=0; bash "$KIT_DIR/lib/spec/spec-active.sh" --bogus "$R" >/dev/null 2>&1 || cli_rc=$?
eq "CLI exits 64 on an unknown argument" "$cli_rc" "64"
cli_rc=0; bash "$KIT_DIR/lib/spec/spec-active.sh" --live >/dev/null 2>&1 || cli_rc=$?
eq "CLI exits 64 with no root" "$cli_rc" "64"
for opt in "set -e" "set -u" "set -euo pipefail"; do
  got=$(bash -c "$opt; . '$KIT_DIR/lib/spec/spec-active.sh'; spec_active --live --branch feat/x_gamma '$R'; spec_active --slug nope '$R' || true; spec_active --live --branch '' '$E' || true; echo done" 2>&1)
  eq "sourced under '$opt'" "$got" "branch${TAB}$R/docs/specs/SPEC-030-gamma.md
done"
done
eq "sourcing sets no shell option" "$(bash -c ". '$KIT_DIR/lib/spec/spec-active.sh'; echo \$-")" "$(bash -c 'echo $-')"

echo
echo "pass=$PASS fail=$FAIL"
[ "$FAIL" -eq 0 ]
