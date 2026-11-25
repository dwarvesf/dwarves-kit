#!/usr/bin/env bash
# test-adapters.sh -- the module suite of lib/adapters: the manifest grammar, the Python loader
# (lib/sync/adapters.py) and its bash twin (lib/sync/adapters.sh), the frozen core lists, and the pytest roots.
#
# Every adapter directory here is a fixture under a scratch dir (KIT_ADAPTERS_DIR), never the live one; no
# case reaches a store or a service. `bin/test-affected` selects this suite for any change under lib/adapters.
#
# Run: bash lib/adapters/tests/test-adapters.sh
set -uo pipefail

KIT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
export KIT_CONFIG_OPERATOR="${TMPDIR:-/tmp}/kit-adapters-none.$$"
PASS=0; FAIL=0
ok()  { PASS=$((PASS+1)); printf '  PASS %s\n' "$1"; }
bad() { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; }
eq()  { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (want '$3', got '$2')"; fi; }
has() { case "$2" in *"$3"*) ok "$1" ;; *) bad "$1 (missing '$3' in '$2')" ;; esac; }
# eqd: eq for multi-line output; a mismatch prints a unified diff of the two instead of both blobs
eqd() {
  if [ "$2" = "$3" ]; then ok "$1"; return; fi
  bad "$1"; command diff <(printf '%s\n' "$3") <(printf '%s\n' "$2") | sed -n '1,12p' | cut -c1-400 | sed 's/^/      /'
}

W="$(mktemp -d "${TMPDIR:-/tmp}/kit-adapters.XXXXXX")" || exit 1
W="$(cd "$W" && pwd -P)"
trap 'command rm -rf "$W"' EXIT
unset KIT_ADAPTERS_DIR KIT_PROJECT_ROOT DWARVES_KIT

PY="$(command -v python3)"
FIXTURE="$KIT/lib/sync/tests/fixtures/adapters"
SH="$KIT/lib/sync/adapters.sh"

# ---- readers ------------------------------------------------------------------------------------
cat > "$W/pydump.py" <<'EOF'
import sys

sys.path.insert(0, sys.argv[1])
import adapters  # noqa: E402

mode, arg = sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else ""
try:
    reg = adapters.load(warn=lambda m: sys.stderr.write(m + "\n"))
    if mode == "rows":
        for d, f in reg.rows(arg):
            print("\t".join([d] + f))
    elif mode == "verb":
        hit = reg.verb(arg)
        if hit is None:
            sys.exit(1)
        print("\t".join([hit[0]] + hit[1]))
    elif mode == "dir":
        print(reg.dir)
except SystemExit as e:
    if e.code not in (None, 0, 1):
        sys.stderr.write(str(e.code) + "\n")
    sys.exit(1 if e.code else 0)
EOF
# sh_run <bash> <dir|-> <function and args...>: run a reader function under the given bash; "-" leaves
# KIT_ADAPTERS_DIR unset
sh_run() {
  local shell="$1" dir="$2"; shift 2
  if [ "$dir" = "-" ]; then env -u KIT_ADAPTERS_DIR "$shell" -c 'set -euo pipefail; . "$0"; "$@"' "$SH" "$@"
  else KIT_ADAPTERS_DIR="$dir" "$shell" -c 'set -euo pipefail; . "$0"; "$@"' "$SH" "$@"; fi
}
py_run() {  # py_run <dir|-> <mode> [arg]
  local dir="$1"; shift
  if [ "$dir" = "-" ]; then env -u KIT_ADAPTERS_DIR "$PY" -I "$W/pydump.py" "$KIT/lib/sync" "$@"
  else KIT_ADAPTERS_DIR="$dir" "$PY" -I "$W/pydump.py" "$KIT/lib/sync" "$@"; fi
}

# mk <dir> <name> <printf format of the manifest> [nopy]: an adapter directory with a stub entry module
mk() {
  mkdir -p "$1/$2"
  printf "$3" > "$1/$2/adapter.tsv"
  [ "${4:-}" = nopy ] || printf 'from __future__ import annotations\n\n\ndef build(app, opts, ctx):\n    return None\n' > "$1/$2/adapter.py"
}

echo "=== files and the language floor ==="
for f in lib/sync/adapters.py lib/sync/adapters.sh lib/adapters/README.md lib/adapters/tests/conftest.py \
         lib/sync/tests/test_adapters.py lib/sync/tests/fixtures/adapters/fake/adapter.tsv lib/sync/tests/fixtures/adapters/fake/adapter.py; do
  [ -f "$KIT/$f" ] && ok "$f exists" || bad "$f is missing"
done
cat > "$W/floor.py" <<'EOF'
import ast
import sys

bad = []
for path in sys.argv[1:]:
    tree = ast.parse(open(path).read(), feature_version=(3, 9))
    body = tree.body[1:] if tree.body and isinstance(tree.body[0], ast.Expr) and isinstance(
        getattr(tree.body[0], "value", None), ast.Constant) and isinstance(tree.body[0].value.value, str) else tree.body
    first = body[0] if body else None
    if not (isinstance(first, ast.ImportFrom) and first.module == "__future__"
            and [a.name for a in first.names] == ["annotations"]):
        bad.append(path + ": the first statement is not `from __future__ import annotations`")
print("\n".join(bad))
EOF
newpy=""
for f in lib/sync/adapters.py lib/adapters/tests/conftest.py lib/adapters/tests/test_conformance.py lib/adapters/tests/test_body_expander.py \
         lib/sync/tests/test_adapters.py lib/sync/tests/fixtures/adapters/fake/adapter.py "$KIT"/lib/adapters/*/adapter.py; do
  case "$f" in /*) ;; *) f="$KIT/$f" ;; esac
  [ -f "$f" ] && newpy="$newpy $f"
done
# shellcheck disable=SC2086
floor_out="$("$PY" "$W/floor.py" $newpy 2>&1)"
eq "every new Python file parses as 3.9 and starts with the future import" "$floor_out" ""
printf 'match x:\n    case 1:\n        pass\n' > "$W/match.py"
if "$PY" "$W/floor.py" "$W/match.py" >/dev/null 2>&1; then bad "negative control: a planted match statement passed the 3.9 parse"
else ok "negative control: a planted match statement fails the 3.9 parse"; fi
printf 'import os\n' > "$W/nofuture.py"
[ -n "$("$PY" "$W/floor.py" "$W/nofuture.py")" ] && ok "negative control: a missing future import is reported" || bad "a missing future import was not reported"
if [ -x /usr/bin/python3 ]; then
  sys_py="$(/usr/bin/python3 -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import adapters; print("imported")' "$KIT/lib/sync" 2>&1)"
  eq "adapters.py imports under /usr/bin/python3 ($(/usr/bin/python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])' 2>/dev/null))" "$sys_py" "imported"
else ok "no /usr/bin/python3 here: the system interpreter import is skipped"; fi
/bin/bash -n "$SH" 2>/dev/null && ok "adapters.sh parses under /bin/bash" || bad "adapters.sh does not parse under /bin/bash"
sh_silence="$(/bin/bash -c 'set -euo pipefail; . "$0"' "$SH" 2>&1; echo "rc=$?")"
eq "sourcing adapters.sh prints nothing and succeeds under set -euo pipefail (/bin/bash)" "$sh_silence" "rc=0"
bash_silence="$(bash -c 'set -euo pipefail; . "$0"' "$SH" 2>&1; echo "rc=$?")"
eq "the same under PATH bash" "$bash_silence" "rc=0"

if [ "$(/bin/bash -c 'echo "${BASH_VERSINFO[0]}"')" -lt 4 ]; then
  { cat "$SH"; printf '\ndeclare -A planted_bash4_only\n'; } > "$W/adapters-bash4.sh"
  if /bin/bash -c 'set -euo pipefail; . "$0"' "$W/adapters-bash4.sh" >/dev/null 2>&1; then
    bad "negative control: a planted bash 4 construct passed under /bin/bash"
  else ok "negative control: a planted bash 4 construct (declare -A) fails under /bin/bash"; fi
else ok "/bin/bash is bash 4 or newer here: the bash 3.2 control is skipped"; fi

echo "=== both readers on the fixture adapter ==="
for kind in app opt secret verb sweep-opt leg const hook; do
  p="$(py_run "$FIXTURE" rows "$kind" 2>&1)"
  for shell in bash /bin/bash; do
    b="$(sh_run "$shell" "$FIXTURE" adapters_rows "$kind" 2>&1)"
    eq "rows of kind $kind agree ($shell)" "$b" "$p"
  done
done
[ -n "$(py_run "$FIXTURE" rows app)" ] && ok "the fixture lists its three apps" || bad "the fixture lists no app"
eq "a verb resolves the same" "$(sh_run /bin/bash "$FIXTURE" adapters_verb fakeverb)" "$(py_run "$FIXTURE" verb fakeverb)"
sh_run bash "$FIXTURE" adapters_verb next >/dev/null 2>&1 && bad "a core verb resolved through the adapters" || ok "a core verb never resolves (returns 1 at once)"
sh_run bash "$FIXTURE" adapters_verb nosuchverb >/dev/null 2>&1 && bad "an unknown verb resolved" || ok "an unknown verb returns 1"
eq "a constant keeps its field with spaces" "$(sh_run bash "$FIXTURE" adapters_rows const | awk -F'\t' '$2 == "inbox-heading" {print $3}')" "### Fixture inbox"
eq "the help text keeps its spaces in a field" "$(sh_run bash "$FIXTURE" adapters_rows opt | head -n 1 | awk -F'\t' '{print $NF}')" "name of the fixture store (a field with spaces)"

# CRLF and a trailing field: the same rows come back
mkdir -p "$W/crlf/fake"; cp "$FIXTURE/fake/adapter.py" "$W/crlf/fake/"
sed 's/$/\r/' "$FIXTURE/fake/adapter.tsv" > "$W/crlf/fake/adapter.tsv"
for kind in app opt const; do
  eq "CRLF manifest: rows of kind $kind match the LF fixture (bash)" "$(sh_run bash "$W/crlf" adapters_rows "$kind" | sed "s#$W/crlf#$FIXTURE#")" "$(py_run "$FIXTURE" rows "$kind")"
  eq "CRLF manifest: rows of kind $kind match the LF fixture (python)" "$(py_run "$W/crlf" rows "$kind" | sed "s#$W/crlf#$FIXTURE#")" "$(py_run "$FIXTURE" rows "$kind")"
done

# negative control: change one row after the Python run, the comparison must fail
cp -R "$FIXTURE" "$W/mutant"
sed 's/two-way/pull-only/' "$FIXTURE/fake/adapter.tsv" > "$W/mutant/fake/adapter.tsv"
if [ "$(sh_run bash "$W/mutant" adapters_rows app | sed "s#$W/mutant#$FIXTURE#")" = "$(py_run "$FIXTURE" rows app)" ]; then
  bad "negative control: a changed mode still compared equal"; else ok "negative control: a changed mode makes the readers differ"; fi

echo "=== each grammar rule: both readers fail with the same line ==="
mkdir -p "$W/bad"
# bad_case <label> <expected fragment>: the adapter dir $W/bad/<label> is already built
bad_case() {
  local d="$W/bad/$1" b p brc prc
  b="$(sh_run bash "$d" adapters_rows app 2>&1 >/dev/null)"; brc=$?
  p="$(py_run "$d" rows app 2>&1 >/dev/null)"; prc=$?
  b="$(printf '%s' "$b" | grep '^adapters:' | head -n 1)"; p="$(printf '%s' "$p" | grep '^adapters:' | head -n 1)"
  if [ "$brc" -ne 0 ] && [ "$prc" -ne 0 ] && [ "$b" = "$p" ] && [ -n "$b" ]; then
    case "$b" in *"$2"*) ok "$1: $2" ;; *) bad "$1: wanted '$2', both readers said: $b" ;; esac
  else bad "$1: readers disagree or one passed (bash rc=$brc '$b', python rc=$prc '$p')"; fi
}
mk "$W/bad/scope" a 'opt\tflag-a\tkey_a\tmaybe\thelp\n';                           bad_case scope "bad scope 'maybe'"
mk "$W/bad/env" a 'secret\tlower\tkey_a\n';                                       bad_case env "bad ENV name 'lower'"
mk "$W/bad/envname" a 'secret\tPATH\tkey_a\n';                                    bad_case envname "reserved ENV name 'PATH'"
mk "$W/bad/envprefix" a 'secret\tKIT_TOKEN\tkey_a\n';                             bad_case envprefix "reserved ENV prefix 'KIT_' in 'KIT_TOKEN'"
mk "$W/bad/sweepenv" a 'sweep-opt\tflag-a\tSWEEP_X\thelp\n';                      bad_case sweepenv "reserved ENV prefix 'SWEEP_'"
mk "$W/bad/dotdot" a 'verb\tgo\t../x.sh\n';                                       bad_case dotdot "bad script path '../x.sh'"
mk "$W/bad/abs" a 'verb\tgo\t/bin/x\n';                                           bad_case abs "bad script path '/bin/x'"
mk "$W/bad/legdotdot" a 'leg\tlast\tlegs/../../x.sh\n';                           bad_case legdotdot "bad script path"
mkdir -p "$W/bad/symlink/a"; : > "$W/bad/symlink/real.sh"; ln -s ../real.sh "$W/bad/symlink/a/x.sh"
mk "$W/bad/symlink" a 'verb\tgo\tx.sh\n';                                         bad_case symlink "script 'x.sh' is a symlink"
mkdir -p "$W/bad/legsym/a"; : > "$W/bad/legsym/real.sh"; ln -s ../real.sh "$W/bad/legsym/a/l.sh"
mk "$W/bad/legsym" a 'leg\tlast\tl.sh\n';                                         bad_case legsym "script 'l.sh' is a symlink"
mk "$W/bad/dirname" Bad_Name 'verb\tgo\tx.sh\n';                                  bad_case dirname "bad adapter directory name 'Bad_Name'"
mk "$W/bad/dupflag" a 'opt\tflag-a\tkey_a\t-\th\nopt\tflag-a\tkey_b\t-\th\n';      bad_case dupflag "duplicate flag 'flag-a'"
mk "$W/bad/dupkey" a 'opt\tflag-a\tkey_a\t-\th\nopt\tflag-b\tkey_a\t-\th\n';       bad_case dupkey "duplicate key 'key_a'"
mk "$W/bad/dupconst" a 'const\tmirror-label\tX\nconst\tmirror-label\tY\n';        bad_case dupconst "duplicate const 'mirror-label'"
mk "$W/bad/duphook" a 'app\tx\ttwo-way\nhook\tbody_expander\nhook\tbody_expander\n'; bad_case duphook "duplicate hook 'body_expander'"
mk "$W/bad/dupapp" a 'app\tx\ttwo-way\n'; mk "$W/bad/dupapp" b 'app\tx\ttwo-way\n'; bad_case dupapp "duplicate app 'x'"
mk "$W/bad/dupverb" a 'verb\tgo\tx.sh\n'; mk "$W/bad/dupverb" b 'verb\tgo\ty.sh\n'; bad_case dupverb "duplicate verb 'go'"
mk "$W/bad/dupenv" a 'secret\tFAKE_A\tkey_a\nsweep-opt\tflag-a\tFAKE_A\thelp\n'; bad_case dupenv "duplicate ENV 'FAKE_A'"
mk "$W/bad/dupsweep" a 'sweep-opt\tflag-a\tFAKE_A\th\nsweep-opt\tflag-a\tFAKE_B\th\n'; bad_case dupsweep "duplicate sweep flag 'flag-a'"
mk "$W/bad/coreflag" a 'opt\tapps\tfake_apps\t-\th\n';                             bad_case coreflag "flag 'apps' is a core engine flag"
mk "$W/bad/coredest" a 'opt\tzzz\tdry_run\t-\th\n';                               bad_case coredest "key 'dry_run' is a core engine dest"
mk "$W/bad/coresweep" a 'sweep-opt\tposter\tFAKE_P\th\n';                         bad_case coresweep "flag 'poster' is a core sweep flag"
mk "$W/bad/secreturl" a 'secret\tFAKE_T\tfake_ref\nopt\tfake-url\tfake_url\t-\th\n'; bad_case secreturl "opt key 'fake_url' has scope - and sits beside a secret row"
mk "$W/bad/secrettarget" a 'opt\tfake-target\tfake_target\t-\th\nsecret\tFAKE_T\tfake_ref\n'; bad_case secrettarget "opt key 'fake_target' has scope -"
mk "$W/bad/coreverb" a 'verb\tnext\tx.sh\n';                                      bad_case coreverb "verb 'next' is a core verb"
mk "$W/bad/mode" a 'app\tx\tsideways\n';                                          bad_case mode "bad mode 'sideways'"
mk "$W/bad/arity" a 'app\tx\n';                                                   bad_case arity "app needs 2 fields"
mk "$W/bad/arityopt" a 'opt\tflag-a\tkey_a\t-\n';                                 bad_case arityopt "opt needs at least 4 fields"
mk "$W/bad/empty" a 'app\tx\t\n';                                                 bad_case empty "empty field"
mk "$W/bad/nopy" a 'app\tx\ttwo-way\n' nopy;                                      bad_case nopy "adapter.py is missing"
mk "$W/bad/nopyhook" a 'hook\tguard\n' nopy;                                      bad_case nopyhook "adapter.py is missing"
mk "$W/bad/phase" a 'leg\tmiddle\tlegs/x.sh\n';                                   bad_case phase "bad phase 'middle'"
mk "$W/bad/hookname" a 'hook\tmystery\n';                                         bad_case hookname "bad hook name 'mystery'"
mk "$W/bad/constname" a 'const\tBad\tX\n';                                        bad_case constname "bad const name 'Bad'"
mk "$W/bad/flagname" a 'opt\tBad\tkey_a\t-\th\n';                                 bad_case flagname "bad flag 'Bad'"
mk "$W/bad/keyname" a 'opt\tflag-a\tBad\t-\th\n';                                 bad_case keyname "bad key 'Bad'"
mk "$W/bad/appname" a 'app\tBad\ttwo-way\n';                                      bad_case appname "bad app name 'Bad'"
mk "$W/bad/verbname" a 'verb\tBad\tx.sh\n';                                       bad_case verbname "bad verb 'Bad'"

# the fixed row loads (the negative control of the bad-row table)
mk "$W/good" a 'opt\tflag-a\tkey_a\t-\thelp\n'
[ "$(sh_run bash "$W/good" adapters_rows opt | wc -l | tr -d ' ')" = 1 ] && [ -n "$(py_run "$W/good" rows opt)" ] \
  && ok "the same row with the fault fixed loads in both readers" || bad "a valid row did not load"

# an unknown kind: the loader warns once and loads the rest; the bash reader stays silent
mk "$W/unknown" a 'mystery\tx\napp\tx\ttwo-way\n'
perr="$(py_run "$W/unknown" rows app 2>&1 >/dev/null)"
has "an unknown row kind warns from the Python loader" "$perr" "unknown row kind 'mystery' (ignored)"
eq "the rest of that adapter still loads (python)" "$(py_run "$W/unknown" rows app 2>/dev/null | awk -F'\t' '{print $2}')" "x"
eq "the bash reader loads it silently" "$(sh_run bash "$W/unknown" adapters_rows app 2>&1 | awk -F'\t' '{print $2}')" "x"

echo "=== the directory ==="
for shell in bash /bin/bash; do
  rc=0; msg="$(KIT_ADAPTERS_DIR=rel/dir "$shell" -c '. "$0"; adapters_dir' "$SH" 2>&1)" || rc=$?
  eq "a relative KIT_ADAPTERS_DIR is refused ($shell)" "$rc:$msg" "1:adapters: KIT_ADAPTERS_DIR must be an absolute path"
  rc=0; msg="$(KIT_ADAPTERS_DIR= "$shell" -c '. "$0"; adapters_dir' "$SH" 2>&1)" || rc=$?
  eq "an empty KIT_ADAPTERS_DIR is refused ($shell)" "$rc:$msg" "1:adapters: KIT_ADAPTERS_DIR must be an absolute path"
done
rc=0; msg="$(KIT_ADAPTERS_DIR=rel/dir "$PY" -I "$W/pydump.py" "$KIT/lib/sync" dir 2>&1)" || rc=$?
eq "a relative KIT_ADAPTERS_DIR is refused (python)" "$rc:$msg" "1:adapters: KIT_ADAPTERS_DIR must be an absolute path"
rc=0; msg="$(KIT_ADAPTERS_DIR= "$PY" -I "$W/pydump.py" "$KIT/lib/sync" dir 2>&1)" || rc=$?
eq "an empty KIT_ADAPTERS_DIR is refused (python)" "$rc:$msg" "1:adapters: KIT_ADAPTERS_DIR must be an absolute path"
eq "the default is lib/adapters of the running kit (bash)" "$(sh_run bash - adapters_dir)" "$KIT/lib/adapters"
eq "the default is lib/adapters of the running kit (python)" "$(py_run - dir)" "$KIT/lib/adapters"
# the decoy: a fixture repo with its own lib/adapters, cwd and the project and kit variables pointing at it
mkdir -p "$W/decoyrepo/lib/adapters/decoy"
printf 'app\tdecoy-app\ttwo-way\n' > "$W/decoyrepo/lib/adapters/decoy/adapter.tsv"
printf 'from __future__ import annotations\nopen(%s, "w").write("ran")\n\n\ndef build(app, opts, ctx):\n    return None\n' "'$W/decoy.marker'" > "$W/decoyrepo/lib/adapters/decoy/adapter.py"
# the kit's own adapters are in the default directory, so the decoy test compares with a run from a neutral cwd
base_py="$(cd "$W" && env -u KIT_ADAPTERS_DIR "$PY" -I "$W/pydump.py" "$KIT/lib/sync" rows app)"
base_sh="$(cd "$W" && env -u KIT_ADAPTERS_DIR bash -c '. "$0"; adapters_rows app' "$SH")"
dec="$(cd "$W/decoyrepo" && KIT_PROJECT_ROOT="$W/decoyrepo" DWARVES_KIT="$W/decoyrepo" env -u KIT_ADAPTERS_DIR "$PY" -I "$W/pydump.py" "$KIT/lib/sync" rows app)"
eq "python never loads a decoy adapter from cwd, KIT_PROJECT_ROOT or DWARVES_KIT" "$dec" "$base_py"
dec="$(cd "$W/decoyrepo" && KIT_PROJECT_ROOT="$W/decoyrepo" DWARVES_KIT="$W/decoyrepo" env -u KIT_ADAPTERS_DIR bash -c '. "$0"; adapters_rows app' "$SH")"
eq "bash never loads a decoy adapter from cwd, KIT_PROJECT_ROOT or DWARVES_KIT" "$dec" "$base_sh"
[ ! -e "$W/decoy.marker" ] && ok "the decoy module never ran" || bad "the decoy adapter module ran"
# no kit.toml key selects the directory: plant the plausible ones in the project, operator and kit-root files
mkdir -p "$W/cfg/op" "$W/cfg/root"
for f in "$W/decoyrepo/.kit.toml" "$W/cfg/op/kit.toml" "$W/cfg/root/kit.toml"; do
  printf '[adapters]\ndirs = "%s/lib/adapters"\ndir = "%s/lib/adapters"\n[sync]\nadapters_dir = "%s/lib/adapters"\n' "$W/decoyrepo" "$W/decoyrepo" "$W/decoyrepo" > "$f"
done
cfgenv=(KIT_PROJECT_ROOT="$W/decoyrepo" KIT_CONFIG_OPERATOR="$W/cfg/op" KIT_CONFIG_ROOT="$W/cfg/root")
eq "no kit.toml key selects the directory (python)" "$(cd "$W/decoyrepo" && env -u KIT_ADAPTERS_DIR "${cfgenv[@]}" "$PY" -I "$W/pydump.py" "$KIT/lib/sync" rows app)" "$base_py"
eq "no kit.toml key selects the directory (bash)" "$(cd "$W/decoyrepo" && env -u KIT_ADAPTERS_DIR "${cfgenv[@]}" bash -c '. "$0"; adapters_rows app' "$SH")" "$base_sh"
[ ! -e "$W/decoy.marker" ] && ok "the decoy module still never ran" || bad "a kit.toml key made the loader run the decoy"
# a missing directory is zero adapters and silent; an unreadable one is a load error
eq "a missing directory loads zero adapters silently (bash)" "$(sh_run bash "$W/nosuchdir" adapters_rows app 2>&1; echo "rc=$?")" "rc=0"
eq "a missing directory loads zero adapters silently (python)" "$(py_run "$W/nosuchdir" rows app 2>&1; echo "rc=$?")" "rc=0"
mkdir -p "$W/locked/a"; printf 'app\tx\ttwo-way\n' > "$W/locked/a/adapter.tsv"; chmod 000 "$W/locked"
if [ -r "$W/locked" ]; then ok "unreadable directory: skipped (this account can read it anyway)"
else
  b="$(sh_run bash "$W/locked" adapters_rows app 2>&1 >/dev/null)"; p="$(py_run "$W/locked" rows app 2>&1 >/dev/null)"
  eq "an unreadable directory is a load error with one line (bash)" "$b" "adapters: cannot read $W/locked"
  eq "an unreadable directory is a load error with one line (python)" "$p" "adapters: cannot read $W/locked"
fi
chmod 755 "$W/locked"
# the kit installs lib through a symlink on this host: the default directory still resolves physically
mkdir -p "$W/linkkit"; ln -s "$KIT/lib" "$W/linkkit/lib"
eq "bash resolves the default directory through a symlinked lib" "$(env -u KIT_ADAPTERS_DIR bash -c '. "$0"; adapters_dir' "$W/linkkit/lib/sync/adapters.sh")" "$KIT/lib/adapters"
ln -s "$KIT/lib/sync/adapters.sh" "$W/adapters-link.sh"
eq "bash resolves the default directory through a symlinked file" "$(env -u KIT_ADAPTERS_DIR bash -c '. "$0"; adapters_dir' "$W/adapters-link.sh")" "$KIT/lib/adapters"
eq "python resolves the default directory through a symlinked lib" "$(env -u KIT_ADAPTERS_DIR "$PY" -I -c 'import sys; sys.path.insert(0, sys.argv[1]); import adapters; print(adapters.adapters_dir())' "$W/linkkit/lib/sync")" "$KIT/lib/adapters"

echo "=== the real manifests ==="
real=0
for m in "$KIT"/lib/adapters/*/adapter.tsv; do
  [ -f "$m" ] || continue
  real=$((real+1))
done
for kind in app opt secret verb sweep-opt leg const hook; do
  for shell in bash /bin/bash; do
    eq "the real set: rows of kind $kind agree ($shell, python)" "$(sh_run "$shell" - adapters_rows "$kind" 2>&1)" "$(py_run - rows "$kind" 2>&1)"
  done
done
mkdir -p "$W/empty"
for shell in bash /bin/bash; do
  eq "an empty directory has no rows and no error under set -euo pipefail ($shell)" "$(sh_run "$shell" "$W/empty" adapters_rows app 2>&1; echo "rc=$?")" "rc=0"
  sh_run "$shell" "$W/empty" adapters_verb mirror >/dev/null 2>&1 && bad "an empty directory resolved a verb ($shell)" || ok "an empty directory resolves no verb ($shell)"
  sh_run "$shell" - adapters_verb nosuchverb >/dev/null 2>&1 && bad "the default directory resolved an unknown verb ($shell)" || ok "the default directory resolves no unknown verb ($shell)"
done
eq "an empty directory loads zero adapters in Python" "$(py_run "$W/empty" rows app 2>&1; echo "rc=$?")" "rc=0"
ok "the real set holds $real adapter manifest(s); the loader skips lib/adapters/tests and docs"

echo "=== the frozen core lists ==="
# CORE_VERBS: the main() labels of board.sh (none of them is an adapter verb) plus the first token of each
# alternative in the backlog.sh usage braces.
main_labels="$(awk '/^main\(\) \{/{m=1;next} m && /^}/{m=0} m && /^    [-a-z|]+\)/{sub(/^    /,""); sub(/\).*/,""); print}' "$KIT/lib/board/board.sh" | tr '|' '\n' | grep -E '^[a-z][a-z-]*$')"
usage_line="$(grep -m1 'usage: backlog.sh {' "$KIT/lib/board/backlog.sh")"
backlog_verbs="$(printf '%s' "$usage_line" | sed 's/.*usage: backlog.sh {//; s/}.*//' | tr '|' '\n' | awk '{print $1}')"
expected="$(printf '%s\n%s\n' "$main_labels" "$backlog_verbs" | sort -u | tr '\n' ' ')"
actual="$(bash -c '. "$0"; printf "%s\n" $CORE_VERBS' "$SH" | sort -u | tr '\n' ' ')"
eq "CORE_VERBS equals the main() labels and the backlog.sh verbs (minus the adapter verbs)" "$actual" "$expected"
cp "$SH" "$W/adapters-mut.sh"; sed -i.bak 's/^CORE_VERBS="all /CORE_VERBS="/' "$W/adapters-mut.sh"
mut="$(bash -c '. "$0"; printf "%s\n" $CORE_VERBS' "$W/adapters-mut.sh" | sort -u | tr '\n' ' ')"
[ "$mut" != "$expected" ] && ok "negative control: dropping a verb from CORE_VERBS breaks the equality" || bad "a dropped core verb still compared equal"
engine_core="$(grep -oE 'add_argument\([^)]*' "$KIT/lib/sync/backlog_sync.py" | grep -oE '"--[a-z][a-z-]*"' | tr -d '"' | sed 's/^--//' | grep -vE '^(list|notion-|github-repo|hermes-|multica-)' | sort -u | tr '\n' ' ')"
want_engine="$(bash -c '. "$0"; printf "%s\n" $ADAPTERS_ENGINE_FLAGS' "$SH" | grep -vx help | sort -u | tr '\n' ' ')"
eq "ADAPTERS_ENGINE_FLAGS equals the engine flags that stay core" "$engine_core" "$want_engine"
sweep_flags="$(awk '/^while \[ \$# -gt 0 \]; do case/{m=1;next} m && /^esac; done/{m=0} m' "$KIT/lib/sync/sweep/board-sweep" | grep -oE '^  --?[a-z][a-z|-]*\)' | tr -d ' )' | tr '|' '\n' | grep -E '^--' | sed 's/^--//' | grep -vxE 'mirror-hermes-home|mirror-snapshot|expire-kinds-file' | sort -u | tr '\n' ' ')"
want_sweep="$(bash -c '. "$0"; printf "%s\n" $ADAPTERS_SWEEP_FLAGS' "$SH" | sort -u | tr '\n' ' ')"
eq "ADAPTERS_SWEEP_FLAGS equals the sweep flags that stay core" "$sweep_flags" "$want_sweep"

echo "=== board.sh resolves adapter verbs from the manifests ==="
BOARD="$KIT/lib/board/board.sh"
cat > "$W/verbs.md" <<'MD'
# BACKLOG

| ID | Item | Notes & source | Status |
|---|---|---|---|
| ID-001 | first thing | n | queued |
MD
mkdir -p "$W/ext/vx"
printf 'verb\tfakeverb\trun.sh\tfirst-arg\nverb\tpyverb\trun.py\n' > "$W/ext/vx/adapter.tsv"
printf '#!/bin/bash\nprintf "sh|%%s|n=%%s|lib=%%s\\n" "$1" "$#" "${KIT_LIB:-unset}"\nfor a in "$@"; do printf "[%%s]" "$a"; done; echo\n' > "$W/ext/vx/run.sh"
printf 'import os, sys\nprint("py|" + "|".join(sys.argv[1:]) + "|lib=" + os.environ.get("KIT_LIB", "unset"))\n' > "$W/ext/vx/run.py"
bsh() { local d="$1"; shift; env -u KIT_LIB KIT_ADAPTERS_DIR="$d" bash "$BOARD" "$@"; }
real_next="$(env -u KIT_ADAPTERS_DIR bash "$BOARD" next --backlog-file "$W/verbs.md" 2>&1)"
eq "board next prints the first queued id" "$real_next" "ID-001"
for dir in "$W/empty" "$W/no-such-dir"; do
  eq "board next works with $(basename "$dir") as the adapter directory" "$(bsh "$dir" next --backlog-file "$W/verbs.md" 2>&1)" "ID-001"
  eq "board get works with $(basename "$dir") as the adapter directory" "$(bsh "$dir" get ID-001 --backlog-file "$W/verbs.md" 2>&1)" "$(env -u KIT_ADAPTERS_DIR bash "$BOARD" get ID-001 --backlog-file "$W/verbs.md" 2>&1)"
  cp "$W/verbs.md" "$W/verbs-set.md"
  bsh "$dir" set ID-001 claimed --backlog-file "$W/verbs-set.md" >/dev/null 2>&1 && grep -q 'claimed' "$W/verbs-set.md" && ok "board set works with $(basename "$dir") as the adapter directory" || bad "board set failed with $(basename "$dir") as the adapter directory"
  out="$(bsh "$dir" mirror --backlog-file "$W/verbs.md" 2>&1)"; rc=$?
  eq "board mirror with no adapter ends in the usage line, exit 64 ($(basename "$dir"))" "$rc" "64"
  has "board mirror with no adapter prints the backlog.sh usage ($(basename "$dir"))" "$out" "usage: backlog.sh"
done
out="$(bsh "$W/ext" fakeverb "a b" c 2>&1)"
eq "an adapter verb runs under bash: manifest args first, then the caller's, spaces kept, KIT_LIB exported" "$out" "$(printf 'sh|first-arg|n=3|lib=%s\n[first-arg][a b][c]' "$KIT/lib")"
eq "a .py verb runs under python3 with the caller's args" "$(bsh "$W/ext" pyverb x "y z" 2>&1)" "py|x|y z|lib=$KIT/lib"
[ "$(bsh "$W/ext" fakeverb 2>&1 | head -n 1)" != "$(bsh "$W/empty" fakeverb --backlog-file "$W/verbs.md" 2>&1 | head -n 1)" ] && ok "present differs from absent: the same verb resolves only with its adapter" || bad "absent and present read alike"
eq "an inherited KIT_LIB is replaced by the real one for a verb script" "$(env KIT_LIB=/nonexistent KIT_ADAPTERS_DIR="$W/ext" bash "$BOARD" pyverb 2>&1)" "py||lib=$KIT/lib"
# a manifest error is global for a verb lookup, but a core verb never reads the manifests
mkdir -p "$W/brokenext/bx"; printf 'verb\tnext\tnope.sh\n' > "$W/brokenext/bx/adapter.tsv"
eq "a core verb ignores a broken manifest" "$(bsh "$W/brokenext" next --backlog-file "$W/verbs.md" 2>&1)" "ID-001"
out="$(bsh "$W/brokenext" fakeverb 2>&1)"; rc=$?
[ "$rc" -ne 0 ] && ok "an unknown verb with a broken manifest ends non-zero ($rc)" || bad "an unknown verb with a broken manifest ended 0"
has "an unknown verb with a broken manifest names the bad row" "$out" "adapters: $W/brokenext/bx/adapter.tsv:1:"
for verb in mirror status writeback mirror-cleanup hermes; do
  hit="$(sh_run bash - adapters_verb "$verb" 2>&1)"
  case "$hit" in "$KIT/lib/adapters/hermes/"*) ok "the real set resolves $verb to the hermes directory" ;; *) bad "the real set resolves $verb to '$hit'" ;; esac
  script="${hit%%$'\t'*}"; [ -f "$script" ] && ok "the script of $verb exists" || bad "the script of $verb is missing: $script"
  hit2="$(sh_run /bin/bash - adapters_verb "$verb" 2>&1)"; eq "the same under /bin/bash for $verb" "$hit2" "$hit"
done
echo "=== board help names the effective adapter directory ==="
has "board help shows the in-tree directory" "$(env -u KIT_ADAPTERS_DIR bash "$BOARD" help)" "adapter directory: $KIT/lib/adapters"
has "board help shows KIT_ADAPTERS_DIR when set" "$(bsh "$W/ext" help)" "adapter directory: $W/ext"
bash -c 'set -euo pipefail; "$@"' _ env KIT_ADAPTERS_DIR=relative bash "$BOARD" help >/dev/null 2>&1; eq "board help still prints with a bad KIT_ADAPTERS_DIR" "$?" "0"

echo "=== the moved bridge scripts derive KIT_LIB from their own location ==="
# A decoy lib/ holds a mega/box.sh and a board/parse-board.sh that write a marker if anything sources them; an
# inherited KIT_LIB that names it, or a path that does not exist, must change nothing.
mkdir -p "$W/decoy/mega" "$W/decoy/board"
printf 'touch "%s/decoy-used"\n' "$W" | tee "$W/decoy/mega/box.sh" > "$W/decoy/board/parse-board.sh"
HERMES_DIR="$KIT/lib/adapters/hermes"
for kl in /nonexistent "$W/decoy"; do
  want_hash="$(env -u KIT_LIB bash "$HERMES_DIR/board-mirror.sh" row-hash r ID-1 t n queued 2>&1)"
  eq "board-mirror.sh ignores KIT_LIB=$(basename "$kl")" "$(KIT_LIB="$kl" bash "$HERMES_DIR/board-mirror.sh" row-hash r ID-1 t n queued 2>&1)" "$want_hash"
  eq "board-writeback.sh ignores KIT_LIB=$(basename "$kl")" "$(KIT_LIB="$kl" bash "$HERMES_DIR/board-writeback.sh" reverse-native triage 2>&1)" "$(env -u KIT_LIB bash "$HERMES_DIR/board-writeback.sh" reverse-native triage 2>&1)"
  KIT_LIB="$kl" "$PY" "$HERMES_DIR/board-mirror-cleanup.py" --help >/dev/null 2>&1 && ok "board-mirror-cleanup.py runs with KIT_LIB=$(basename "$kl")" || bad "board-mirror-cleanup.py failed with KIT_LIB=$(basename "$kl")"
done
[ ! -e "$W/decoy-used" ] && ok "the decoy lib was never sourced" || bad "a moved script sourced the inherited KIT_LIB"
# negative control: a temp copy that trusts the environment must source the decoy
mkdir -p "$W/mut/lib/adapters"; cp -R "$KIT/lib/board" "$KIT/lib/mega" "$W/mut/lib/"; cp -R "$HERMES_DIR" "$W/mut/lib/adapters/"
sed -i.bak 's|^KIT_LIB="$(cd "$BM_DIR/../.." \&\& pwd)"|KIT_LIB="${KIT_LIB:-$(cd "$BM_DIR/../.." \&\& pwd)}"|' "$W/mut/lib/adapters/hermes/board-mirror.sh"
KIT_LIB="$W/decoy" bash "$W/mut/lib/adapters/hermes/board-mirror.sh" row-hash r ID-1 t n queued >/dev/null 2>&1
[ -e "$W/decoy-used" ] && ok "negative control: a script that trusts KIT_LIB sources the decoy" || bad "the decoy control did not fire"
command rm -f "$W/decoy-used"

echo "=== the frozen surface ==="
# the flags and sweep flags live jobs pass; each must still be accepted and listed
FROZEN_ENGINE="apps backlog archive-file state-root dry-run filter scope-exit-cap allow-scope-exit allow-flips allow-archived-closes list notion-db notion-parent notion-title github-repo hermes-target hermes-home hermes-board hermes-assignee hermes-workspace notion-taskboard-db notion-taskboard-status-map notion-taskboard-status-default notion-taskboard-priority-map notion-taskboard-weight-map notion-taskboard-owner notion-taskboard-props notion-taskboard-types notion-taskboard-pull-db notion-taskboard-pull-props notion-taskboard-pull-done-option multica-url multica-workspace multica-project"
engine_help() { env -u KIT_ADAPTERS_DIR ${1:+KIT_ADAPTERS_DIR="$1"} "$PY" "$KIT/lib/sync/backlog_sync.py" --help 2>&1; }
missing_flags() { local help="$1" f miss=""; shift; for f in "$@"; do case "$help" in *"--$f"*) ;; *) miss="$miss --$f" ;; esac; done; printf '%s' "$miss"; }
# shellcheck disable=SC2086
eq "backlog_sync.py --help lists every frozen engine flag" "$(missing_flags "$(engine_help)" $FROZEN_ENGINE)" ""
sweep_help="$(env -u KIT_ADAPTERS_DIR bash "$KIT/bin/board" sweep --help 2>&1)"
has "board sweep --help prints Usage: board sweep" "$sweep_help" "Usage: board sweep"
eq "board sweep --help lists the three leg flags" "$(missing_flags "$sweep_help" mirror-hermes-home mirror-snapshot expire-kinds-file)" ""
# negative control: one opt row deleted from a temp copy of the set must be named
mkdir -p "$W/frozen"; for d in "$KIT"/lib/adapters/*/; do n="$(basename "$d")"; [ -f "$d/adapter.tsv" ] && cp -R "$d" "$W/frozen/$n"; done
grep -v $'^opt\thermes-target\t' "$KIT/lib/adapters/hermes/adapter.tsv" > "$W/frozen/hermes/adapter.tsv"
# shellcheck disable=SC2086
mutant_missing="$(missing_flags "$(engine_help "$W/frozen")" $FROZEN_ENGINE)"
eq "negative control: a deleted opt row makes the frozen-flag loop name its flag" "$mutant_missing" " --hermes-target"
# every [sync] key of kit.toml that starts with an app prefix is read by an opt row, a secret row or a derived filter key
reg_keys="$({ sh_run bash - adapters_rows opt | awk -F'\t' '{print $3}'; sh_run bash - adapters_rows secret | awk -F'\t' '{print $3}'
  sh_run bash - adapters_rows app | awk -F'\t' '{a=$2; gsub(/-/,"_",a); m=$3; print a "_only_tags"; print a "_skip_tags"; if (m=="two-way") print a "_intake"}'; } | sort -u)"
toml_keys="$(awk '/^\[sync\]/{f=1;next} /^\[/{f=0} f && /^[a-z_]+ *=/ {print $1}' "$KIT/kit.toml" | grep -E '^(reminders|notion|hermes|multica|github)_' | sort -u)"
unread="$(comm -23 <(printf '%s\n' "$toml_keys") <(printf '%s\n' "$reg_keys") | tr '\n' ' ')"
eq "every app-prefixed [sync] key of kit.toml is read by a manifest row" "$unread" ""
unread_mut="$(comm -23 <(printf '%s\n' "$toml_keys") <(printf '%s\n' "$reg_keys" | grep -vx hermes_target) | tr '\n' ' ')"
eq "negative control: dropping a key from the registry set is reported" "$unread_mut" "hermes_target "

echo "=== no adapter configured: board sync ==="
mkdir -p "$W/syncrepo/_meta"; git -C "$W/syncrepo" init -q 2>/dev/null
cp "$W/verbs.md" "$W/syncrepo/_meta/BACKLOG.md"
sync_cfg() { printf '[sync]\napps = "%s"\n' "$1" > "$W/syncrepo/.kit.toml"; }
sync_run() { local d="$1"; shift; ( cd "$W/syncrepo" && env KIT_ADAPTERS_DIR="$d" KIT_DATA_ROOT="$W/syncdata" KIT_CONFIG_OPERATOR="$W/none.toml" bash "$KIT/bin/board" sync --backlog-file "$W/syncrepo/_meta/BACKLOG.md" "$@" 2>&1 ); }
before="$(cksum < "$W/syncrepo/_meta/BACKLOG.md")"
sync_cfg x; out="$(sync_run "$W/empty")"; rc=$?
eq "apps = x with no adapter exits 1" "$rc" "1"
has "apps = x names the adapter directory" "$out" "no adapter provides x (searched: $W/empty)"
sync_cfg "github,x"; out="$(sync_run "$W/empty")"; rc=$?
eq "apps = github,x with no adapter exits 1 before any sync" "$rc" "1"
has "the first unknown app is named" "$out" "no adapter provides github (searched: $W/empty)"
eq "the board is byte identical after the refused runs" "$(cksum < "$W/syncrepo/_meta/BACKLOG.md")" "$before"
eq "the refused runs wrote no state file" "$(find "$W/syncdata" -type f 2>/dev/null | wc -l | tr -d ' ')" "0"
sync_cfg fake-pull; out="$(sync_run "$FIXTURE" --dry-run)"
case "$out" in *"no adapter provides"*) bad "absent differs from present: the fixture adapter was not found ($out)" ;; *) ok "absent differs from present: the fixture adapter provides fake-pull" ;; esac

echo "=== bash 3.2 (/bin/bash) and a symlinked kit root ==="
mkdir -p "$W/shim"; ln -s /bin/bash "$W/shim/bash"
# a stub python3 for the sync case, a stub hermes for the bridge cases, a stub secret reader
mkdir -p "$W/stubs"
printf '#!/bin/bash\nprintf "ARGV:%%s\\nFAKE_TOKEN:%%s\\n" "$*" "${FAKE_TOKEN:+set}"\n' > "$W/stubs/python3"
printf '#!/bin/bash\nprintf "stub-secret\\n"\n' > "$W/stubs/secret-cache-read"
printf '#!/bin/bash\ncase "$*" in *"list --json"*) echo "[]" ;; *"boards list"*) echo "[]" ;; *) echo "{}" ;; esac\n' > "$W/stubs/hermes"
chmod +x "$W/stubs/python3" "$W/stubs/secret-cache-read" "$W/stubs/hermes"
mkdir -p "$W/opcfg"; printf '[sync]\nfake_token_ref = "op://operator/ref"\n' > "$W/opcfg/kit.toml"
mkdir -p "$W/fxrepo/_meta"; git -C "$W/fxrepo" init -q 2>/dev/null
cp "$W/verbs.md" "$W/fxrepo/_meta/BACKLOG.md"
printf '[sync]\napps = "fake-two"\n' > "$W/fxrepo/.kit.toml"
printf 'fx %s on\n' "$W/fxrepo/_meta/BACKLOG.md" > "$W/fxrepo/boards.txt"
: > "$W/fxrepo/snap.jsonl"
git -C "$W/fxrepo" add -A >/dev/null 2>&1; git -C "$W/fxrepo" -c user.email=t@t -c user.name=t commit -qm init >/dev/null 2>&1
base_env() { env -i HOME="$W/home" TMPDIR="$W" KIT_DATA_ROOT="$W/shdata" KIT_CONFIG_OPERATOR="$W/opcfg" HERMES_BIN="$W/stubs/hermes" HERMES_HOME="$W/hh" "$@"; }
mkdir -p "$W/home"
# norm: the parts of an output that differ between two runs of the same case (a clock, a scratch name, the kit root's spelling)
norm() { sed -e 's/synced: [0-9T:.Z-]*/synced: <T>/g' -e 's#board-mirror-registry\.[A-Za-z0-9]*#board-mirror-registry.<R>#g' -e "s#$W/kitroot#$KIT#g"; }
# run_case <PATH> <label...> -> prints the stdout and stderr of the case, normalized
shim_cases() {  # shim_cases <kit-root> <path-prefix>: board sync over the fixture adapter, a stub python3 and a secret row
  local root="$1" pfx="$2" P out
  P="$pfx$W/stubs:/usr/bin:/bin"
  out="$(cd "$W/fxrepo" && base_env PATH="$P" KIT_ADAPTERS_DIR="$FIXTURE" bash "$root/bin/board" sync --backlog-file "$W/fxrepo/_meta/BACKLOG.md" 2>&1; echo "rc=$?")"
  printf '%s\n' "$out" | norm
}
sh_bash="$(shim_cases "$KIT" "")"
sh_shim="$(shim_cases "$KIT" "$W/shim:")"
eqd "board sync (stub python3, a secret row) gives the same output under /bin/bash and PATH bash" "$sh_shim" "$sh_bash"
has "the secret row reached the stub engine by environment" "$sh_shim" "FAKE_TOKEN:set"
case "$sh_shim" in *stub-secret*) bad "the secret leaked into argv or output" ;; *) ok "the secret never appears in the output" ;; esac

bridge_cases() {  # bridge_cases <path-prefix> [kit-root]
  local pfx="$1" root="${2:-$KIT}" out="" P
  P="$pfx$W/stubs:/usr/bin:/bin"
  for c in "mirror --dry-run" "status" "status --with-mega" "writeback --dry-run"; do
    out="$out--- $c
$(cd "$W/fxrepo" && base_env ${BR_AD:+KIT_ADAPTERS_DIR="$BR_AD"} PATH="$P" bash "$root/bin/board" $c --repo-root "$W/fxrepo" --registry "$W/fxrepo/boards.txt" --snapshot "$W/fxrepo/snap.jsonl" 2>&1; echo "rc=$?")
"
  done
  printf '%s' "$out" | norm
}
b_bash="$(bridge_cases "")"
b_shim="$(bridge_cases "$W/shim:")"
eqd "mirror, status, status --with-mega and writeback give the same output under /bin/bash" "$b_shim" "$b_bash"
has "the mirror dry run printed a plan" "$b_shim" "--- mirror --dry-run"
has "status printed its summary line" "$b_shim" "repos changed since last mirror"
has "status --with-mega printed the rollup header" "$b_shim" "MEGA ROLLUP:"
case "$b_shim" in *"rc=0"*) ok "the bridge verbs ran to an exit code under /bin/bash" ;; *) bad "no bridge case ran: $b_shim" ;; esac
case "$b_shim" in *"rc=127"*|*"command not found"*|*"syntax error"*) bad "a bridge verb hit a bash 3.2 error: $b_shim" ;; *) ok "no bash 3.2 error in the bridge verbs" ;; esac

sweep_case() {  # sweep_case <path-prefix>
  local pfx="$1" P
  P="$pfx/usr/bin:/bin"
  printf '#!/bin/bash\necho "board called: $*"\nexit 0\n' > "$W/sweepboard"; chmod +x "$W/sweepboard"
  : > "$W/sweep-boards.txt"
  mkdir -p "$W/sweep-home/.local/bin"; command cp -f "$W/stubs/hermes" "$W/sweep-home/.local/bin/hermes"
  printf '[]\n' > "$W/kinds.json"
  env -i HOME="$W/sweep-home" TMPDIR="$W" KIT_CONFIG_OPERATOR="$W/none.toml" PATH="$P" bash "$KIT/bin/board" sweep --registry "$W/sweep-boards.txt" --board-cmd "$W/sweepboard" --repo-root "$W/sweep-home" --dry-run \
    --mirror-hermes-home "$W/hh" --mirror-snapshot "$W/sweep-snap.jsonl" --expire-kinds-file "$W/kinds.json" 2>&1 | sed "s#$W#<W>#g; s#[0-9]\{4\}-[0-9][0-9]-[0-9][0-9][T ][0-9:]*Z\{0,1\}#<T>#g; s#pid [0-9]*#pid <N>#g; s#board-mirror-registry\.[A-Za-z0-9]*#board-mirror-registry.<R>#g"
  echo "rc=${PIPESTATUS[0]}"
}
s_bash="$(sweep_case "")"
s_shim="$(sweep_case "$W/shim:")"
eqd "board sweep with the three leg flags gives the same output under /bin/bash" "$s_shim" "$s_bash"
has "the mirror leg ran under /bin/bash" "$s_shim" "mirror rc="
has "the expire leg ran under /bin/bash" "$s_shim" "expire rc="
eq "board sweep --help is the same under /bin/bash" "$(env -u KIT_ADAPTERS_DIR PATH="$W/shim:$PATH" bash "$KIT/bin/board" sweep --help 2>&1)" "$sweep_help"

# a kit root with bin and lib symlinked to the tree, as this host installs the kit
mkdir -p "$W/kitroot"; ln -s "$KIT/bin" "$W/kitroot/bin"; ln -s "$KIT/lib" "$W/kitroot/lib"
eq "board sweep --help through a symlinked kit root" "$(env -u KIT_ADAPTERS_DIR bash "$W/kitroot/bin/board" sweep --help 2>&1)" "$sweep_help"
sl_sync="$(shim_cases "$W/kitroot" "")"
eqd "board sync through a symlinked kit root" "$sl_sync" "$sh_bash"
sl_bridge="$(bridge_cases "" "$W/kitroot")"
eqd "the bridge verbs through a symlinked kit root (KIT_ADAPTERS_DIR unset)" "$sl_bridge" "$b_bash"
# KIT_ADAPTERS_DIR set to a scratch path outside the tree: an extension directory that symlinks the built-ins it wants
EXT="$W/extdir"; mkdir -p "$EXT"; ln -s "$KIT/lib/adapters/hermes" "$EXT/hermes"
ext_bridge="$(BR_AD="$EXT" bridge_cases "" "$W/kitroot")"
eqd "the bridge verbs through a symlinked kit root and an extension directory of symlinks" "$ext_bridge" "$b_bash"
case "$EXT" in /var/folders/*|/private/var/folders/*) ok "the extension directory is under /var/folders" ;; *) ok "the extension directory is a scratch path ($EXT); /var/folders applies on macOS" ;; esac

echo "=== discovery ==="
# bin/test-affected and run-all collect suites through tests/lib/suites.sh; a change under lib/adapters picks this suite
# by the module rule only when the file below is collected under this id
disc="$(cd "$KIT" && bash -c '. tests/lib/suites.sh; suite_list; suite_id lib/adapters/tests/test-adapters.sh')"
has "suites.sh collects the module suite" "$disc" "lib/adapters/tests/test-adapters.sh"
has "the module suite goes by lib-adapters-test-adapters" "$disc" "lib-adapters-test-adapters"
has "suites.sh collects the purity suite" "$disc" "tests/test-core-purity.sh"

echo "=== the pytest roots ==="
uv run --no-project --with pytest -- pytest "$KIT/lib/adapters/tests" -q > "$W/pytest.out" 2>&1; prc=$?
if [ "$prc" -eq 0 ] || [ "$prc" -eq 5 ]; then ok "pytest lib/adapters/tests: exit $prc (5 means no tests yet)"
else bad "pytest lib/adapters/tests exit $prc: $(tail -n 3 "$W/pytest.out" | tr '\n' ' ')"; fi

printf '=== %d passed, %d failed ===\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
