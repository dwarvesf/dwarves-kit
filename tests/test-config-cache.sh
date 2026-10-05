#!/usr/bin/env bash
# test-config-cache.sh -- the read-once cache in lib/config/kit-config.sh (spec SPEC-398).
#
# 1. Parity: for every section.key in the repo kit.toml plus a set of tricky fixture tomls
#    (quotes, comments, arrays, duplicate keys, dotted sections, empty values, CRLF, a BOM, regex
#    metacharacter keys, missing, empty, directory and unreadable layers, project over operator
#    over root), kit_config_get, kit_config_get_root and the raw _kit_toml_get return exactly what
#    the frozen pre-cache resolver (tests/lib/kit-config-reference.sh) returns. Run through
#    `$(...)` like the real callers, in-process, and in reverse order, under bash 3.2 and the
#    PATH bash. KIT_CONFIG_REFERENCE=<file> swaps in another oracle (e.g. master's copy).
# 2. Cache behaviour: a layer edited mid-process, a different project root, a reused path with new
#    content, more paths than slots, and the number of awk runs (counted by a PATH shim).
#
# Run: bash tests/test-config-cache.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
LIB="$KIT_DIR/lib/config/kit-config.sh"
REF="${KIT_CONFIG_REFERENCE:-$KIT_DIR/tests/lib/kit-config-reference.sh}"
DRV="$KIT_DIR/tests/lib/config-parity-driver.sh"
REAL_AWK="$(command -v awk)"

PASS=0; FAIL=0
ok() { if [ "$2" = 0 ]; then PASS=$((PASS+1)); echo "  PASS $1"; else FAIL=$((FAIL+1)); echo "  FAIL $1"; fi; }
chk() { [ "$2" = "$3" ] && ok "$1" 0 || { ok "$1 (got [$2] want [$3])" 1; }; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
FX="$T/fx"; mkdir -p "$FX"

# --- fixtures: one dir each, holding the same text as kit.toml (operator/root) and .kit.toml (project)
mkfx() { mkdir -p "$FX/$1"; cat > "$FX/$1/kit.toml"; cp "$FX/$1/kit.toml" "$FX/$1/.kit.toml"; }

mkfx quotes <<'EOF'
[q]
a = "x"
b = "x
c = x"
d = ""
e = "  padded  "
f = 'single'
g = "a # not comment"
h = "he said \"hi\""
i = ""quoted""
j = " "
k = "
l = """
m=bare
n =	tabbed
EOF
mkfx comments <<'EOF'
# top comment
[c]
# full = ignored
   # indented = ignored
k1 = v1 # trailing
k2 = v2#nospace
k3 = # only comment
k4 = "v4" # after quotes
	k5 = tab indent
[c] # header comment
k6 = after header comment
EOF
mkfx arrays <<'EOF'
[a]
arr = ["x", "y"]
multi = [
  "p",
  "q",
]
after = 1
  ["lone","line"],
tail = 2
[ a.b ]
v = 1
[[tbl]]
k = in-array-table
EOF
mkfx dups <<'EOF'
[d]
dup = first
dup = second
e1 =
e1 = z
[other]
x = 1
[d]
dup = third
more = m
EOF
mkfx dotted <<'EOF'
[lane.normal]
phases = ["spec", "build"]
light = ["x"]
[lane.full]
phases = ["a"]
[ lane.spaced ]
phases = ["s"]
[lane.normal.sub]
k = deep
[lane]
normal.phases = oops
EOF
: > "$T/empty.toml"; mkdir -p "$FX/empty"; cp "$T/empty.toml" "$FX/empty/kit.toml"; cp "$T/empty.toml" "$FX/empty/.kit.toml"
mkfx onlycomments <<'EOF'
# nothing here
# [s]
# k = v
EOF
mkdir -p "$FX/nonl"; printf '[n]\nlast = no-newline' > "$FX/nonl/kit.toml"; cp "$FX/nonl/kit.toml" "$FX/nonl/.kit.toml"
mkdir -p "$FX/crlf"; printf '[w]\r\nk = v\r\nq = "x"\r\n' > "$FX/crlf/kit.toml"; cp "$FX/crlf/kit.toml" "$FX/crlf/.kit.toml"
mkdir -p "$FX/bom"; printf '\357\273\277[b]\nk = after-bom\n[c]\nk = ok\n' > "$FX/bom/kit.toml"; cp "$FX/bom/kit.toml" "$FX/bom/.kit.toml"
mkfx noheader <<'EOF'
top = before-any-section
[s]
k = v
EOF
mkfx spaces <<'EOF'
[ws]
k=v
k2  =  v2
  k3 = v3
k4	=	v4
key with space = nope
UPPER = u
Mixed_case-1 = m
EOF
mkfx meta <<'EOF'
[meta]
a+b = plus
x.* = star
k* = kstar
k = plain
(paren) = p
[m.e.t.a]
dots = d
EOF
mkfx values <<'EOF'
[v]
path = "C:\\dir\tx"
uni = héllo wörld
eq = a=b
eq2 = =x
hash = "a#b"
sp = a   b
bs = back\slash
EOF
mkfx base <<'EOF'
[ledger]
location = "shared"   # inline comment
[mega]
wave_cap = 2
[gauntlet]
runner_host = "root-host"
[lane.normal]
phases = ["spec", "build"]
EOF
mkfx over <<'EOF'
[ledger]
location = "isolated"
[mega]
wave_cap =
[gauntlet]
runner_host = "evil-host"
[knowledge]
root = "/tmp/proj"
EOF
mkfx oper <<'EOF'
[ledger]
location = "operator"
[mega]
wave_cap = 9
[gauntlet]
runner_host = "operator-host"
EOF
mkdir -p "$FX/real"; cp "$KIT_DIR/kit.toml" "$FX/real/kit.toml"; cp "$KIT_DIR/kit.toml" "$FX/real/.kit.toml"
mkdir -p "$FX/dirfile/kit.toml" "$FX/dirfile/.kit.toml"          # a directory where the file should be
mkdir -p "$FX/unread"; printf '[u]\nk = secret-less\n' > "$FX/unread/kit.toml"; cp "$FX/unread/kit.toml" "$FX/unread/.kit.toml"
chmod 000 "$FX/unread/kit.toml" "$FX/unread/.kit.toml"
NONE="$T/none"                                                    # no such dir: layer missing

# --- keys: every section.key of every fixture (crude independent scan) plus awkward extras
scan_keys() {
  awk '
    /^[ \t]*#/ { next }
    /^[ \t]*\[/ { h = $0; sub(/#.*/, "", h); gsub(/[][ \t\r]/, "", h); sec = h; next }
    sec != "" && /^[ \t]*[^ \t=]+[ \t]*=/ { k = $0; sub(/=.*/, "", k); gsub(/[ \t\r]/, "", k); print sec "." k }
  ' "$1" 2>/dev/null
}
KEYS="$T/keys.txt"
for f in "$FX"/*/kit.toml; do [ -r "$f" ] && scan_keys "$f"; done | LC_ALL=C sort -u > "$KEYS"
cat >> "$KEYS" <<'EOF'
nope.nope
ghost.key
q.zzz
.top
top.top
top
a.tail
tbl.k
a.b.v
lane.normal.phases
lane.normal.sub.k
lane.spaced.phases
lane.normal
d.dup
d.e1
meta.k*
meta.x.*
meta.a+b
m.e.t.a.dots
q.
.k
b.k
c.k
EOF
sort -u "$KEYS" -o "$KEYS"
NKEYS="$(wc -l < "$KEYS" | tr -d ' ')"

# --- cases: `project|operator|root|fn|arg1|arg2` rows, numbered below
PRE="$T/pre.txt"; : > "$PRE"; CASES="$T/cases.txt"
TRIPLES="$T/triples.txt"; : > "$TRIPLES"
tri() { printf '%s|%s|%s\n' "$FX/$1" "$FX/$2" "$FX/$3" >> "$TRIPLES"; }
for f in quotes comments arrays dups dotted empty onlycomments nonl crlf bom noheader spaces meta values dirfile unread; do
  printf '%s|%s|%s\n' "$NONE" "$NONE" "$FX/$f" >> "$TRIPLES"          # only the root layer
  printf '%s|%s|%s\n' "$FX/$f" "$NONE" "$FX/base" >> "$TRIPLES"       # project over root
done
tri over oper base; tri oper over base; tri over over base; tri base over oper; tri dups quotes comments
tri dotted base arrays; tri over base base; tri empty empty empty; tri crlf bom nonl
tri real over oper; tri over oper real; tri over real real
printf '%s|%s|%s\n' "$NONE" "$NONE" "$NONE" >> "$TRIPLES"
# each triple: the keys its three files define, plus a few absent and shared ones
while IFS='|' read -r P O R; do
  { for d in "$P" "$O" "$R"; do scan_keys "$d/kit.toml"; done
    printf 'nope.nope\nq.zzz\n.top\nlane.normal.phases\nmega.wave_cap\nledger.location\n'; } | LC_ALL=C sort -u |
  while IFS= read -r k; do
    echo "$P|$O|$R|get|$k|D"
    echo "$P|$O|$R|root|$k|"
  done
done < "$TRIPLES" >> "$PRE"
# the awkward-key list against several triples
for tr in "$FX/over|$FX/oper|$FX/base" "$NONE|$NONE|$FX/meta" "$NONE|$NONE|$FX/arrays"; do
  while IFS= read -r k; do echo "$tr|get|$k|D"; echo "$tr|root|$k|"; done < "$KEYS"
done >> "$PRE"
# raw getter: every fixture's .kit.toml (the file path rides in the project slot) x its own keys
# plus the absent and awkward ones
for d in "$FX"/*/; do
  { scan_keys "${d}kit.toml"; printf 'nope.nope\n.top\nq.zzz\nmeta.k*\nlane.normal.phases\nd.dup\n'; } | LC_ALL=C sort -u |
  while IFS= read -r k; do echo "${d}.kit.toml|$NONE|$NONE|tg|${k%.*}|${k##*.}"; done
done >> "$PRE"
awk '{ print NR "|" $0 }' "$PRE" > "$CASES"
NCASES="$(wc -l < "$CASES" | tr -d ' ')"
echo "=== config-cache: $NCASES parity cases over $NKEYS keys, $(ls "$FX" | wc -l | tr -d ' ') fixtures ==="

# --- 1. parity
run_drv() { # <shell> <lib> <mode> <cases> <out>
  ( cd "$FX/base" && "$1" "$DRV" "$2" "$3" < "$4" > "$5" 2>/dev/null )
}
ORACLE="$T/oracle.out"
run_drv /bin/bash "$REF" sub "$CASES" "$ORACLE"
chk "oracle answered every case" "$(wc -l < "$ORACLE" | tr -d ' ')" "$NCASES"
awk 'BEGIN{OFS=""} {a[NR]=$0} END{for(i=NR;i>=1;i--) print a[i]}' "$CASES" > "$T/cases.rev"
SHELLS="/bin/bash"; [ "$(command -v bash)" != /bin/bash ] && SHELLS="/bin/bash $(command -v bash)"
for sh in $SHELLS; do
  v="$("$sh" -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}')"
  for mode in sub direct; do
    run_drv "$sh" "$LIB" "$mode" "$CASES" "$T/new.$mode.out"
    if cmp -s "$ORACLE" "$T/new.$mode.out"; then ok "parity bash $v $mode: $NCASES cases, zero diffs" 0
    else ok "parity bash $v $mode" 1; diff "$ORACLE" "$T/new.$mode.out" | head -8; fi
  done
  [ "$sh" = /bin/bash ] || continue
  run_drv "$sh" "$LIB" direct "$T/cases.rev" "$T/new.rev.out"
  sort -t'|' -k1,1n "$T/new.rev.out" > "$T/new.rev.sorted"
  if cmp -s "$ORACLE" "$T/new.rev.sorted"; then ok "parity bash $v in-process, reversed order: zero diffs" 0
  else ok "parity bash $v reversed" 1; diff "$ORACLE" "$T/new.rev.sorted" | head -8; fi
done
chmod 644 "$FX/unread/kit.toml" "$FX/unread/.kit.toml"

# --- 2. cache behaviour
OUTF="$T/o.txt"
unset KIT_PROJECT_ROOT KIT_CONFIG_OPERATOR KIT_CONFIG_ROOT
mkdir -p "$T/cb/root" "$T/cb/proj" "$T/cb/proj2" "$T/cb/op"
printf '[mega]\nwave_cap = 2\n[ledger]\nlocation = "shared"\n' > "$T/cb/root/kit.toml"
printf '[ledger]\nlocation = "projA"\n' > "$T/cb/proj/.kit.toml"
printf '[ledger]\nlocation = "projB"\n' > "$T/cb/proj2/.kit.toml"
cat > "$T/cb/run.sh" <<'EOF'
# usage: run.sh <lib> ; prints one result per line. Direct calls only, so the shell's own cache is used.
. "$1"
g() { kit_config_get "$@" > "$OUTF"; V="$(cat "$OUTF")"; }
r() { kit_config_get_root "$@" > "$OUTF"; V="$(cat "$OUTF")"; }
export KIT_CONFIG_ROOT="$T/cb/root" KIT_CONFIG_OPERATOR="$T/cb/none" KIT_PROJECT_ROOT="$T/cb/proj"
g mega.wave_cap;     echo "1 $V"
# same size, same second: only the content differs
printf '[mega]\nwave_cap = 7\n[ledger]\nlocation = "shared"\n' > "$T/cb/root/kit.toml"
g mega.wave_cap;     echo "2 $V"
g ledger.location;   echo "3 $V"
KIT_PROJECT_ROOT="$T/cb/proj2" g ledger.location; echo "4 $V"
KIT_PROJECT_ROOT="$T/cb/proj"  g ledger.location; echo "5 $V"
printf '[ledger]\nlocation = "projC"\n' > "$T/cb/proj/.kit.toml"
g ledger.location;   echo "6 $V"
mv -f "$T/cb/proj/.kit.toml" "$T/cb/proj/.kit.toml.gone"
g ledger.location;   echo "7 $V"
printf '[ledger]\nlocation = "opA"\n' > "$T/cb/op/kit.toml"
KIT_CONFIG_OPERATOR="$T/cb/op" r ledger.location; echo "8 $V"
printf '[ledger]\nlocation = "opB"\n' > "$T/cb/op/kit.toml"
KIT_CONFIG_OPERATOR="$T/cb/op" r ledger.location; echo "9 $V"
# a reused path with new content, 20 distinct paths (more than the slots), then the first again
for n in $(seq 1 20); do mkdir -p "$T/cb/many$n"; printf '[s]\nk = v%s\n' "$n" > "$T/cb/many$n/kit.toml"; done
bad=0
for n in $(seq 1 20); do KIT_CONFIG_ROOT="$T/cb/many$n" KIT_PROJECT_ROOT="$T/cb/none" g s.k; [ "$V" = "v$n" ] || bad=1; done
for n in 1 5 20 3; do KIT_CONFIG_ROOT="$T/cb/many$n" KIT_PROJECT_ROOT="$T/cb/none" g s.k; [ "$V" = "v$n" ] || bad=1; done
echo "10 $bad"
EOF
export T OUTF
for sh in $SHELLS; do
  v="$("$sh" -c 'echo ${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}')"
  # rewrite the fixtures each run so both shells start from the same state
  printf '[mega]\nwave_cap = 2\n[ledger]\nlocation = "shared"\n' > "$T/cb/root/kit.toml"
  printf '[ledger]\nlocation = "projA"\n' > "$T/cb/proj/.kit.toml"; rm -f "$T/cb/proj/.kit.toml.gone"
  res="$("$sh" "$T/cb/run.sh" "$LIB" 2>&1 | tr '\n' ';')"
  chk "bash $v cache: mid-process edit, other root, delete, operator edit, slot recycling" "$res" \
      "1 2;2 7;3 projA;4 projB;5 projA;6 projC;7 shared;8 opA;9 opB;10 0;"
done

# number of awk runs: shim counts them; the parent shell primes at source, every later lookup is awk-free
mkdir -p "$T/shim"
printf '#!/bin/sh\necho x >> "%s/awk.count"\nexec "%s" "$@"\n' "$T" "$REAL_AWK" > "$T/shim/awk"; chmod +x "$T/shim/awk"
mkdir -p "$T/aw/root" "$T/aw/proj"
printf '[mega]\nwave_cap = 2\n[ledger]\nlocation = "shared"\n[gate]\nk = 1\n' > "$T/aw/root/kit.toml"
cat > "$T/aw/run.sh" <<'EOF'
export KIT_CONFIG_ROOT="$T/aw/root" KIT_CONFIG_OPERATOR="$T/aw/none" KIT_PROJECT_ROOT="$T/aw/none"
. "$1"
: > "$T/awk.count"
. "$1"                       # a second source is a no-op (guard) and parses nothing
mark() { printf '%s' "$(wc -l < "$T/awk.count" | tr -d ' ')"; }
kit_config_get mega.wave_cap > /dev/null              # first lookups: parse the root once
a1="$(mark)"
n=0; while [ $n -lt 50 ]; do kit_config_get ledger.location >/dev/null; kit_config_get_root gate.k >/dev/null; kit_config_get nope.nope d >/dev/null; n=$((n+1)); done
a2="$(mark)"
printf '[mega]\nwave_cap = 3\n[ledger]\nlocation = "shared"\n[gate]\nk = 1\n' > "$T/aw/root/kit.toml"   # same size
kit_config_get mega.wave_cap > /dev/null; kit_config_get mega.wave_cap > /dev/null; kit_config_get gate.k >/dev/null
a3="$(mark)"
echo "$a1 $a2 $a3"
EOF
export T
cp "$T/aw/root/kit.toml" "$T/aw/root/kit.toml.orig"
res="$(cd "$T/aw/proj" && PATH="$T/shim:$PATH" /bin/bash "$T/aw/run.sh" "$LIB" 2>&1 | tail -1)"
# awk runs counted since the source: 0 before and after the 150 lookups (primed at source), +1 after the edit
chk "awk runs after source / after 150 lookups / after one edit and 3 lookups" "$res" "0 0 1"
OLDRES="$(cd "$T/aw/proj" && PATH="$T/shim:$PATH" /bin/bash "$T/aw/run.sh" "$REF" 2>&1 | tail -1)"
echo "  info reference resolver, same script: awk runs = $OLDRES (so many, per lookup)"

# KIT_CONFIG_NO_PRIME: a script that only sources the lib spawns no awk, and its first lookup still answers
cat > "$T/aw/np.sh" <<'EOF'
export KIT_CONFIG_ROOT="$T/aw/root" KIT_CONFIG_OPERATOR="$T/aw/none" KIT_PROJECT_ROOT="$T/aw/none"
: > "$T/awk.count"
KIT_CONFIG_NO_PRIME=1 . "$1"
a1="$(wc -l < "$T/awk.count" | tr -d ' ')"
kit_config_get mega.wave_cap > "$T/np.out"
echo "$a1 $(cat "$T/np.out") $(wc -l < "$T/awk.count" | tr -d ' ')"
EOF
res="$(cd "$T/aw/proj" && PATH="$T/shim:$PATH" /bin/bash "$T/aw/np.sh" "$LIB" 2>&1 | tail -1)"
chk "KIT_CONFIG_NO_PRIME: 0 awk at source, value still read, then 1 parse" "$res" "0 3 1"

# no output on load, and a missing HOME under set -u does not abort a caller
out="$(cd "$T/aw/proj" && /bin/bash -c ". '$LIB'" 2>&1)"; chk "sourcing prints nothing" "$out" ""
out="$(cd "$T/aw/proj" && env -u HOME -u XDG_CONFIG_HOME -u DWARVES_KIT -u KIT_CONFIG_ROOT /bin/bash -c "set -euo pipefail; . '$LIB'; kit_config_get a.b dflt" 2>&1)"
chk "unset HOME under set -u: default, no abort" "$out" "dflt"

echo "config-cache: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
