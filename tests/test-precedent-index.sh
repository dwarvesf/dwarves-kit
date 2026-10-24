#!/usr/bin/env bash
# test-precedent-index.sh -- the precedent inventory as the one index for skills and tools:
# new registry kinds (exec, commands, agents), nested skill trees with a label column, the
# `estate` metadata block (SKILL.md frontmatter, tool.toml [estate], a script header line),
# exact-name lookup before keyword scoring, the --layer/--cluster/--kind filters, and the
# `precedent index` markdown page.
#
# Every case runs against a scratch HOME, a scratch ledger and a fixture registry. No estate
# path, tenant name or vendor appears here: the kit is a multi-user product.
#
# Run: bash tests/test-precedent-index.sh

set -uo pipefail
KIT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PRECEDENT_BIN="$KIT_DIR/bin/precedent"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() {
  TOTAL=$((TOTAL+1))
  if [ "$2" -eq 0 ] 2>/dev/null; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1))
  else echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL+1)); fi
}
# check <name> <rc> [detail]: assert on rc, print detail on failure.
check() {
  assert "$1" "$2"
  if [ "$2" -ne 0 ] && [ -n "${3:-}" ]; then printf '%s\n' "$3" | sed 's/^/      /'; fi
}

T="$(mktemp -d "${TMPDIR:-/tmp}/dk-precedent-index.XXXXXX")" || exit 1
T="$(cd "$T" && pwd)"
trap 'rm -rf "$T"' EXIT
KIT_CONFIG_OPERATOR="$T/no-operator-config"; export KIT_CONFIG_OPERATOR

# ---------------------------------------------------------------------------
# Fixture.
# ---------------------------------------------------------------------------
mkx() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2}" > "$1"; chmod +x "$1"; }
mkf() { mkdir -p "$(dirname "$1")"; printf '%s\n' "${2}" > "$1"; }

HOME_D="$T/home"; REPO="$T/repo"; LEDGER="$T/ledger"; REG="$T/registry.txt"
mkdir -p "$HOME_D" "$LEDGER" "$REPO"

# A repo with three tools: an [estate] table, none, and a malformed one.
mkf "$REPO/tools/alpha/tool.toml" 'name = "alpha"
description = "alpha payroll sync tool"
status = "active"

[estate]
layer = "T2"
cluster = "cluster-a"
owner = "ownerone"
callers = ["a", "b"]'
mkx "$REPO/tools/alpha/bin/alpha-run" '#!/usr/bin/env bash
# alpha-run: runs the payroll sync'
mkf "$REPO/tools/beta/tool.toml" 'name = "beta"
description = "beta bare tool"'
mkf "$REPO/tools/gamma/tool.toml" 'name = "gamma"
description = "gamma tool with a broken estate table"

[estate]
layer =
cluster "x"
@@@ owner'
mkf "$REPO/tools/zqrun/tool.toml" 'name = "zqrun"
description = "zq runner wrapper"'
mkx "$REPO/tools/zq-runner-extra/bin/zq-extra" '#!/usr/bin/env bash
# zq-extra: zq runner extras'
mkf "$REPO/tools/zq-runner-extra/tool.toml" 'name = "zq-runner-extra"
description = "zq runner extras, many zq runner words"'
git -C "$REPO" init -q; git -C "$REPO" config user.email t@t; git -C "$REPO" config user.name t
git -C "$REPO" add -A; git -C "$REPO" commit -qm init

# Skills, flat: estate block present, absent, malformed.
SK="$T/skills"
mkf "$SK/sk-full/SKILL.md" '---
name: sk-full
description: Fully declared skill for the index tests.
metadata:
  estate:
    layer: T3
    cluster: cluster-c
    owner: ownertwo
    harness: [claude-code, harness-x]
    drives: [board, estate-run]
    parent: sk-parent
    status: active
---
Body.'
mkf "$SK/sk-bare/SKILL.md" '---
name: sk-bare
description: Skill with no metadata at all.
---
Body.'
mkf "$SK/sk-quoted/SKILL.md" '---
name: sk-quoted
description: "Quoted description for the index. More text."
---
Body.'
mkf "$SK/sk-bad/SKILL.md" '---
name: sk-bad
description: Skill with a malformed estate block.
metadata:
  estate: [oops
    layer
   : :
---
Body.'

# A category-nested tree: SKILL.md at depth 2 and 3, another harness's block under metadata.
HX="$T/tree"
mkf "$HX/hx-flat/SKILL.md" '---
name: hx-flat
description: Flat tree skill.
---'
mkf "$HX/devops/hx-deep/SKILL.md" '---
name: hx-deep
description: Category-nested tree skill.
version: 1.0.0
metadata:
  harnessx:
    tags: [Coding-Agent]
    related_skills: [hx-flat]
  estate:
    layer: T3
    cluster: cluster-b
---'
mkf "$HX/ops/sub/hx-deeper/SKILL.md" '---
name: hx-deeper
description: Two categories down.
---'
mkf "$HX/ops/sub/too/far/hx-toofar/SKILL.md" '---
name: hx-toofar
description: Beyond the walk depth.
---'

# Executables: nested, with decoys that must never be indexed.
EX="$T/execs"
mkx "$EX/zq-runner" '#!/usr/bin/env bash
# zq-runner: runs the zq jobs
# estate: layer=T0 cluster=cluster-b owner=ownerthree'
mkx "$EX/job-a/job-a-run" '#!/usr/bin/env bash
# job-a-run: the job a launcher'
mkx "$EX/job-a/deep/deep-run" '#!/usr/bin/env bash
# deep-run: beyond depth two'
mkx "$EX/job-a/old-run.bak.1" '#!/usr/bin/env bash
# old-run: a backup copy'
mkx "$EX/__pycache__/pyc-run" '#!/usr/bin/env bash
# pyc-run: cache decoy'
mkx "$EX/node_modules/pkg/nm-run" '#!/usr/bin/env bash
# nm-run: vendored decoy'
mkx "$EX/job-a/test-thing" '#!/usr/bin/env bash
# test-thing: a test helper'
mkx "$EX/retired/retired-run" '#!/usr/bin/env bash
# retired-run: a retired job'
mkf "$EX/job-a/notes.txt" '# notes-txt: not executable'
printf '#!/bin/sh\n\0binary' > "$EX/binary-run"; chmod +x "$EX/binary-run"

# A glob row: tools/*/deploy style.
mkx "$T/globbed/p1/deploy/gl-one" '#!/usr/bin/env bash
# gl-one: first globbed exec'
mkx "$T/globbed/p2/deploy/nest/gl-two" '#!/usr/bin/env bash
# gl-two: second globbed exec'

# Commands and agents.
mkf "$T/cmds/cmd-one.md" '---
description: Command one does a thing.
---
# /cmd-one'
mkf "$T/cmds/cmd-two.md" '# /cmd-two

Command two has no frontmatter.'
mkf "$T/agents/ag-one.md" '---
name: ag-one
description: Agent one reviews things.
tools: Read
metadata:
  estate:
    layer: T3
    cluster: cluster-c
---
You are agent one.'

cat > "$REG" <<FIX
repo $REPO
skills $SK label=cc-user
skills $HX label=tree-one
exec $EX depth=2 label=jobs-one
exec $T/globbed/*/deploy depth=3
commands $T/cmds label=cc-cmds
agents $T/agents label=cc-agents
FIX

export HOME="$HOME_D" KIT_LEDGER_DIR="$LEDGER" PRECEDENT_REGISTRY="$REG" REPO_ROOT="$REPO"

# the "# precedent inventory: <query>" header echoes the query, so it is dropped before any grep
find_inv() { "$PRECEDENT_BIN" find --surface inventory "$@" 2>&1 | grep -v '^# precedent inventory'; }
find_json() { "$PRECEDENT_BIN" find --surface inventory --json "$@" 2>&1; }
# first hit line of the first printed section, with the section title: "title|hit"
first_hit() {
  find_inv --quiet "$@" | awk '/^## /{sec=substr($0,4); next} sec && /^  [^ (]/{print sec "|" substr($0,3); exit}'
}
# a here-string, not a pipe: grep -q exits at the first match and pipefail would read the
# writer's SIGPIPE as a failure on a long page
has() { grep -qF -- "$2" <<<"$1"; }

# ---------------------------------------------------------------------------
# Registry grammar.
# ---------------------------------------------------------------------------
OUT="$(find_inv --quiet zzzabsent)"; RC=$?
check "registry: exec/commands/agents kinds and label=/depth= options parse" "$RC" "$OUT"

printf 'bogus %s\n' "$T" > "$T/bad-kind.txt"
OUT="$(find_inv --registry "$T/bad-kind.txt" zzz)"; RC=$?
{ [ "$RC" -eq 64 ] && has "$OUT" "exec"; }; check "registry: unknown kind exits 64 and names the new kinds" $? "rc=$RC $OUT"

printf 'exec %s depth=zz\n' "$T" > "$T/bad-depth.txt"
OUT="$(find_inv --registry "$T/bad-depth.txt" zzz)"; RC=$?
[ "$RC" -eq 64 ]; check "registry: a non-numeric depth= exits 64" $? "rc=$RC $OUT"

printf 'exec %s colour=red\n' "$T" > "$T/bad-opt.txt"
OUT="$(find_inv --registry "$T/bad-opt.txt" zzz)"; RC=$?
[ "$RC" -eq 64 ]; check "registry: an unknown option key exits 64" $? "rc=$RC $OUT"

# ---------------------------------------------------------------------------
# exec kind.
# ---------------------------------------------------------------------------
OUT="$(find_inv job-a-run)"
has "$OUT" "job-a-run"; check "exec: a depth-2 executable is indexed with its header summary" $? "$OUT"
has "$OUT" "the job a launcher"; check "exec: the header comment is the summary" $? "$OUT"

SKIPPED_OK=0
for decoy in deep-run old-run.bak.1 old-run pyc-run nm-run test-thing notes-txt retired-run binary-run; do
  OUT="$(find_inv --limit 50 "$decoy")"
  has "$OUT" "$decoy" && { SKIPPED_OK=1; echo "      indexed decoy: $decoy"; }
done
[ "$SKIPPED_OK" -eq 0 ]; check "exec: depth bound, .bak, __pycache__, node_modules, test*, retired/, non-exec and binary are skipped" $?

OUT="$(find_inv gl-one)"
has "$OUT" "gl-one"; check "exec: a glob row indexes every matched dir" $? "$OUT"
OUT="$(find_inv gl-two)"
has "$OUT" "gl-two"; check "exec: depth=3 reaches a nested executable under a glob match" $? "$OUT"

# ---------------------------------------------------------------------------
# skills: nested trees and the label column.
# ---------------------------------------------------------------------------
OUT="$(find_inv hx-deep)"
has "$OUT" "skill tree-one/hx-deep"; check "skills: a category-nested SKILL.md is indexed and carries the row label" $? "$OUT"
OUT="$(find_inv hx-deeper)"
has "$OUT" "hx-deeper"; check "skills: SKILL.md two categories down is indexed" $? "$OUT"
OUT="$(find_inv hx-toofar)"
{ ! has "$OUT" "hx-toofar"; }; check "skills: the walk is depth-bounded" $? "$OUT"
OUT="$(find_inv hx-flat)"
has "$OUT" "hx-flat"; check "skills: a flat SKILL.md under a labeled row is indexed" $? "$OUT"

mkdir -p "$T/copy/hx-deep"; cp "$HX/devops/hx-deep/SKILL.md" "$T/copy/hx-deep/SKILL.md"
printf 'skills %s label=tree-one\nskills %s label=tree-two\n' "$HX" "$T/copy" > "$T/two-labels.txt"
OUT="$(find_inv --registry "$T/two-labels.txt" --limit 20 hx-deep)"
{ has "$OUT" "tree-one/hx-deep" && has "$OUT" "tree-two/hx-deep"; }
check "skills: the same skill name under two labels is kept as two rows (a copy is visible)" $? "$OUT"

# ---------------------------------------------------------------------------
# commands and agents.
# ---------------------------------------------------------------------------
OUT="$(find_inv cmd-one)"
has "$OUT" "Command one does a thing"; check "commands: a command with frontmatter is indexed by its description" $? "$OUT"
OUT="$(find_inv cmd-two)"
has "$OUT" "Command two has no frontmatter"; check "commands: a command without frontmatter falls back to its first prose line" $? "$OUT"
OUT="$(find_inv ag-one)"
has "$OUT" "Agent one reviews things"; check "agents: an agent definition is indexed by name and description" $? "$OUT"

# ---------------------------------------------------------------------------
# estate metadata, read through the index page.
# ---------------------------------------------------------------------------
IDX="$("$PRECEDENT_BIN" index 2>&1)"; RC=$?
check "index: the verb exits 0" "$RC" "$IDX"
row() { printf '%s\n' "$IDX" | grep -F -- "| $1 " | head -1; }
section_of() { printf '%s\n' "$IDX" | awk -v n="| $1 " 'index($0,"## cluster:")==1{c=$0} index($0,"### layer:")==1{l=$0} index($0,n)==1{print c " / " l; exit}'; }

S="$(section_of sk-full)"
{ has "$S" "cluster: cluster-c" && has "$S" "layer: T3"; }
check "estate: SKILL.md metadata.estate lands the skill under its cluster and layer" $? "$S"
has "$(row sk-full)" "ownertwo"; check "estate: the owner column shows the declared owner" $? "$(row sk-full)"

S="$(section_of sk-bare)"
{ has "$S" "cluster: (blank)" && has "$S" "layer: (blank)"; }
check "estate: a skill with no metadata block is grouped under (blank), not an error" $? "$S"
has "$(row sk-bare)" "(blank)"; check "estate: a missing owner shows as (blank) in the row" $? "$(row sk-bare)"

has "$(row sk-quoted)" "| sk-quoted | Quoted description for the index. |"
check "index: a quoted YAML description loses its quotes in the summary column" $? "$(row sk-quoted)"

S="$(section_of sk-bad)"
{ has "$S" "cluster: (blank)"; }
check "estate: a malformed estate block degrades to blanks and the skill is still indexed" $? "$S"

S="$(section_of hx-deep)"
{ has "$S" "cluster: cluster-b" && has "$S" "layer: T3"; }
check "estate: another harness's metadata block beside estate does not hide the estate block" $? "$S"

S="$(section_of alpha)"
{ has "$S" "cluster: cluster-a" && has "$S" "layer: T2"; }
check "estate: tool.toml [estate] lands the tool under its cluster and layer" $? "$S"
S="$(section_of alpha-run)"
{ has "$S" "cluster: cluster-a" && has "$S" "layer: T2"; }
check "estate: a script under a tool inherits the tool's estate fields" $? "$S"
S="$(section_of beta)"
has "$S" "cluster: (blank)"; check "estate: a tool.toml with no [estate] table is blank, not an error" $? "$S"
S="$(section_of gamma)"
has "$S" "cluster: (blank)"; check "estate: a malformed [estate] table degrades to blanks" $? "$S"
S="$(section_of zq-runner)"
{ has "$S" "cluster: cluster-b" && has "$S" "layer: T0"; }
check "estate: a script header line '# estate: k=v ...' is read" $? "$S"
S="$(section_of ag-one)"
has "$S" "cluster: cluster-c"; check "estate: an agent definition's frontmatter estate block is read" $? "$S"

# ---------------------------------------------------------------------------
# exact-name lookup before keyword scoring.
# ---------------------------------------------------------------------------
# Control: both a tool dir (zq-runner-extra) and an exec (zq-runner) match "zq runner"; the
# tools section sits first in source order and wins a plain keyword tie.
GOT="$(first_hit "zq runner")"
has "$GOT" "zq-runner-extra"; check "exact-name control: a keyword query ranks the tool section first" $? "$GOT"

GOT="$(first_hit zq-runner)"
{ has "$GOT" "exact|" && has "$GOT" "zq-runner" && ! has "$GOT" "zq-runner-extra"; }
check "exact-name: a query equal to an item name returns that item first, in an exact section" $? "$GOT"

GOT="$(first_hit ZQ-Runner)"
has "$GOT" "exact|"; check "exact-name: the match is case-insensitive" $? "$GOT"

OUT="$(find_inv zq-runner)"
CNT="$(printf '%s\n' "$OUT" | grep -cF 'jobs-one/zq-runner')"
[ "$CNT" -eq 1 ]; check "exact-name: the exact item is not repeated in its own section" $? "$OUT"

GOT="$(first_hit sk-full)"
{ has "$GOT" "exact|" && has "$GOT" "sk-full"; }; check "exact-name: a skill is found by its frontmatter name" $? "$GOT"
GOT="$(first_hit cmd-one)"
has "$GOT" "exact|"; check "exact-name: a command is found by its file stem" $? "$GOT"
GOT="$(first_hit alpha-run)"
has "$GOT" "exact|"; check "exact-name: a script under a tool is found by its file name" $? "$GOT"
GOT="$(first_hit kit:assign)"
{ has "$GOT" "exact|" && has "$GOT" "assign"; }; check "exact-name: kit:<name> finds the kit's own command" $? "$GOT"
OUT="$(find_inv --quiet kit:zq-runner)"
{ ! has "$OUT" "## exact"; }; check "exact-name: kit:<name> never matches a non-kit item exactly" $? "$OUT"

JSON="$(find_json zq-runner)"
GOT="$(printf '%s' "$JSON" | python3 -c '
import json,sys
d=json.load(sys.stdin); print(list(d.keys())[1], len(d["exact"]["hits"]))' 2>/dev/null)"
[ "$GOT" = "exact 1" ]; check "exact-name: --json carries an 'exact' key right after the data marker" $? "$GOT"

# --json keeps every section whole (machine readers key on section names): the exact item is
# also still in its own section.
GOT="$(printf '%s' "$JSON" | python3 -c '
import json,sys
d=json.load(sys.stdin); print(any("zq-runner" in h for h in d["executables"]["hits"]))' 2>/dev/null)"
[ "$GOT" = "True" ]; check "exact-name: --json adds the exact key and leaves the sections whole" $? "$GOT"

# --explain resolves the new kinds' labels through the catalog.
OUT="$("$PRECEDENT_BIN" find --explain "command cc-cmds/cmd-one" 2>&1)"
has "$OUT" "Command one does a thing"; check "explain: a command label resolves to its file" $? "$OUT"
OUT="$("$PRECEDENT_BIN" find --explain "jobs-one/zq-runner" 2>&1)"
has "$OUT" "runs the zq jobs"; check "explain: an exec label resolves to its script" $? "$OUT"
OUT="$("$PRECEDENT_BIN" find --explain "jobs-one/../../../etc/hosts" 2>&1)"
{ ! has "$OUT" "localhost"; }; check "explain: a label cannot walk out of the scanned roots" $? "$OUT"

# ---------------------------------------------------------------------------
# filters.
# ---------------------------------------------------------------------------
OUT="$(find_inv --quiet --cluster cluster-c "sk")"
{ has "$OUT" "sk-full" && ! has "$OUT" "sk-bare" && ! has "$OUT" "sk-bad"; }
check "filter: --cluster keeps only items declaring that cluster" $? "$OUT"
OUT="$(find_inv --quiet --layer T0 "zq runner")"
{ has "$OUT" "zq-runner" && ! has "$OUT" "zq-runner-extra"; }
check "filter: --layer keeps only items declaring that layer" $? "$OUT"
OUT="$(find_inv --quiet --kind agent "ag one reviews")"
{ has "$OUT" "ag-one"; }; check "filter: --kind agent keeps agents" $? "$OUT"
OUT="$(find_inv --quiet --kind skill "ag one reviews")"
{ ! has "$OUT" "ag-one"; }; check "filter: --kind skill drops the agent" $? "$OUT"
OUT="$(find_inv --kind nonsense x)"; RC=$?
[ "$RC" -eq 64 ]; check "filter: an unknown --kind exits 64" $? "rc=$RC $OUT"

IDXF="$("$PRECEDENT_BIN" index --cluster cluster-b --kind skill 2>&1)"
{ has "$IDXF" "hx-deep" && ! has "$IDXF" "sk-full" && ! has "$IDXF" "zq-runner"; }
check "filter: the index honours --cluster and --kind" $? "$IDXF"

# ---------------------------------------------------------------------------
# index page.
# ---------------------------------------------------------------------------
H="$(printf '%s\n' "$IDX" | head -1)"
has "$H" "# "; check "index: the page opens with a title" $? "$H"
grep -q '^| name | summary | path | owner | source |' <<<"$IDX"
check "index: rows carry name, summary, path, owner and source" $?
CL="$(printf '%s\n' "$IDX" | grep '^## cluster:' | sed 's/## cluster: //' | tr '\n' ',')"
case "$CL" in cluster-a,cluster-b,cluster-c,\(blank\),) RC=0 ;; *) RC=1 ;; esac
check "index: clusters sort alphabetically and (blank) comes last" "$RC" "$CL"
GAPS="$(printf '%s\n' "$IDX" | grep -i 'without')"
has "$GAPS" "owner"; check "index: a header line counts the items still missing a field" $? "$GAPS"
KINDS="$(printf '%s\n' "$IDX" | grep '^#### ' | sed 's/ (.*//' | sort -u | tr '\n' ' ')"
{ has "$KINDS" "skill" && has "$KINDS" "tool" && has "$KINDS" "script" && has "$KINDS" "command" && has "$KINDS" "agent"; }
check "index: skill, tool, script, command and agent kinds all appear" $? "$KINDS"
{ has "$IDX" "sk-full" && ! has "$IDX" "retired-run" && ! has "$IDX" "pyc-run"; }
check "index: a decoy the scan skips never reaches the page" $? ""

"$PRECEDENT_BIN" index --out "$T/page.md" >/dev/null 2>&1; RC=$?
{ [ "$RC" -eq 0 ] && grep -q 'sk-full' "$T/page.md"; }; check "index: --out writes the page to a file" $? "rc=$RC"

IDX2="$("$PRECEDENT_BIN" index 2>&1)"
[ "$IDX" = "$IDX2" ]; check "index: two runs over the same tree print the same page" $? ""

echo
echo "== summary =="
echo "  $PASS/$TOTAL passed"
[ "$FAIL" -eq 0 ]
