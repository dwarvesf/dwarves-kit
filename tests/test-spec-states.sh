#!/usr/bin/env bash
# The spec `Status:` header is declared once, in lib/spec/states.tsv, and read once, by
# lib/spec/spec-status.sh (docs/briefs/DECISION-BRIEF-declared-state-machines.md).
#
# Why this suite exists: six readers (context-readiness, spec-drift-guard, pre-compact-backup,
# post-compact-reinject, spec-index, goal-drafts) each parsed the header with their own regex and
# disagreed: `**Status:**` (bold) and decorated values such as `VALIDATED (round 4 ...)` or
# `Draft · 2026-07-31 · Owner: Han` counted as live in some and as no header in others. This
# suite pins the table's shape, the header grammar, that every reader agrees on one fixture set,
# and that no code file hardcodes the vocabulary again.
set -uo pipefail

KIT_DIR="${KIT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
TSV="$KIT_DIR/lib/spec/states.tsv"
SS="$KIT_DIR/lib/spec/spec-status.sh"
FAILED=0
pass() { printf 'PASS %s\n' "$1"; }
fail() { printf 'FAIL %s\n' "$1"; FAILED=$((FAILED + 1)); }

TMP=$(mktemp -d "${TMPDIR:-/tmp}/kit.XXXXXX") || exit 1
trap 'rm -rf "$TMP"' EXIT

rows() { awk -F'\t' '!/^#/ && NF' "$TSV"; }

# ---- 1. table shape: 4 tab fields, a known class, every `next` target declared, aliases unique ----
bad="$(rows | awk -F'\t' '
  { st[NR]=$1; cls[NR]=$2; nx[NR]=$3; al[NR]=$4; known[$1]=1; n=NR }
  END {
    for (i=1; i<=n; i++) {
      if (st[i] !~ /^[A-Z]+$/) print st[i] ": state is not upper-case letters"
      if (cls[i] !~ /^(active|hold|terminal)$/) print st[i] ": class " cls[i]
      if (cls[i] == "terminal" && nx[i] != "-") print st[i] ": terminal with a next"
      if (nx[i] == "") print st[i] ": empty next (use -)"
      if (al[i] == "") print st[i] ": empty aliases (use -)"
      if (nx[i] != "-") { k=split(nx[i], t, " "); for (j=1; j<=k; j++) if (!(t[j] in known)) print st[i] ": next " t[j] " undeclared" }
    }
    for (i=1; i<=n; i++) if (al[i] != "-") {
      k=split(al[i], a, " ")
      for (j=1; j<=k; j++) {
        if (a[j] !~ /^[A-Z-]+$/) print st[i] ": alias " a[j] " is not upper-case"
        if (a[j] in known) print st[i] ": alias " a[j] " is also a state"
        if (a[j] in seen) print st[i] ": alias " a[j] " claimed twice"
        seen[a[j]] = 1
      }
    }
  }')"
nf="$(rows | awk -F'\t' 'NF != 4' | wc -l | tr -d ' ')"
if [ -z "$bad" ] && [ "$nf" = 0 ] && [ -n "$(rows)" ]; then pass "states.tsv rows are well-formed"; else fail "states.tsv malformed: ${bad:-$nf rows without 4 fields}"; fi
want_all="$(rows | cut -f1 | paste -sd ' ' -)"
[ "$want_all" = "DRAFT APPROVED VALIDATED SHIPPED PARKED" ] && pass "the canonical states and their order" || fail "states: $want_all"

# ---- 2. get: every alias and every state resolves, in any case ----
spec() {  # spec <name> <content...>: write a fixture, print its path
  local p="$TMP/$1.md"; shift; printf '%s' "$*" > "$p"; printf '%s' "$p"
}
getf() { bash "$SS" get "$1" 2>&1; }
want_get() {  # want_get <label> <expected> <file>
  local got; got="$(getf "$3")"
  [ "$got" = "$2" ] && pass "get: $1" || fail "get: $1 (want $2, got $got)"
}
n=0
while IFS=$'\t' read -r st _ _ al; do
  words="$st"; [ "$al" != "-" ] && words="$st $al"
  for w in $words; do
    n=$((n + 1))
    f="$(spec "w$n" "Status: $w
")"; want_get "$w -> $st" "$st" "$f"
    lw="$(printf '%s' "$w" | tr 'A-Z' 'a-z')"
    f="$(spec "l$n" "status: $lw
")"; want_get "$lw (lower case) -> $st" "$st" "$f"
  done
done < <(rows)

# ---- 3. get: bold, decorated, and odd forms ----
want_get "plain"                  VALIDATED "$(spec f1 $'# T\nStatus: VALIDATED\n')"
want_get "bold"                   VALIDATED "$(spec f2 $'# T\n\n**Status:** VALIDATED\n')"
want_get "bold, colon outside"    PARKED    "$(spec f3 $'**Status**: parked\n')"
want_get "bold + decoration"      VALIDATED "$(spec f4 $'**Status:** VALIDATED (the change lands in the same PR)\n')"
want_get "round decoration"       VALIDATED "$(spec f5 $'Status: VALIDATED (round 4 APPROVED: 0 critical)\n')"
want_get "comma decoration"       VALIDATED "$(spec f6 $'**Status:** VALIDATED, revision 3 (round 2 APPROVED)\n')"
want_get "dot-separated"          DRAFT     "$(spec f7 $'Status: Draft · 2026-07-31 · Owner: Han\n')"
want_get "dot-separated, upper"   APPROVED  "$(spec f8 $'Status: APPROVED · 2026-07-31 · Owner: Han\n')"
want_get "SHIPPED (vX)"           SHIPPED   "$(spec f9 $'Status: SHIPPED (v1.6.0)\n')"
want_get "SHIPPED pending merge"  SHIPPED   "$(spec f10 $'Status: SHIPPED pending merge (branch `x`)\n')"
want_get "IMPLEMENTED, pending"   VALIDATED "$(spec f11 $'Status: IMPLEMENTED, pending merge\n')"
want_get "SHIPPED-PENDING (PR)"   SHIPPED   "$(spec f12 $'Status: SHIPPED-PENDING (PR #125). More.\n')"
want_get "no space after colon"   DRAFT     "$(spec f13 $'Status:DRAFT\n')"
want_get "CRLF line ends"         SHIPPED   "$(spec f14 $'Status: SHIPPED\r\n')"
want_get "frontmatter key"        SHIPPED   "$(spec f15 $'---\nstatus: shipped\n---\n# T\n')"
want_get "only the first header counts" VALIDATED "$(spec f16 $'Status: VALIDATED\nlater\nStatus: parked\n')"
want_get "a Status mid-line is not a header" NONE "$(spec f17 $'# T\nThe Status: SHIPPED claim\n')"
want_get "an indented Status is not a header" NONE "$(spec f18 $'  Status: SHIPPED\n')"
want_get "no header"              NONE      "$(spec n1 $'# T\nbody\n')"
want_get "empty file"             NONE      "$(spec n2 '')"
want_get "missing file"           NONE      "$TMP/does-not-exist.md"
want_get "a directory"             NONE      "$TMP"
want_get "unknown word"           UNKNOWN   "$(spec u1 $'Status: WHATEVER\n')"
want_get "empty value"            UNKNOWN   "$(spec u2 $'Status:\n')"
want_get "a number is no state"   UNKNOWN   "$(spec u3 $'Status: 2026-07-31\n')"

# ---- 4. states and machine verbs ----
got="$(bash "$SS" states | paste -sd ' ' -)"
[ "$got" = "$want_all" ] && pass "states = table" || fail "states: $got"
got="$(bash "$SS" states --class active | paste -sd ' ' -)"
[ "$got" = "$(rows | awk -F'\t' '$2=="active"{print $1}' | paste -sd ' ' -)" ] && pass "states --class active = table" || fail "states --class active: $got"
got="$(bash "$SS" states --class terminal | paste -sd ' ' -)"
[ "$got" = "SHIPPED PARKED" ] && pass "states --class terminal = SHIPPED PARKED" || fail "states --class terminal: $got"
bash "$SS" states --class bogus >/dev/null 2>&1; rc=$?
[ "$rc" = 64 ] && pass "states --class bogus exits 64" || fail "states --class bogus rc=$rc"
out="$(bash "$SS" machine)"
[ "$(printf '%s\n' "$out" | head -1)" = "$(printf 'state\tclass\tnext\taliases')" ] && [ "$(printf '%s\n' "$out" | tail -n +2)" = "$(rows)" ] \
  && pass "machine prints the header and the table" || fail "machine output: $out"
bash "$SS" bogus >/dev/null 2>&1; rc=$?
[ "$rc" = 64 ] && pass "an unknown verb exits 64" || fail "unknown verb rc=$rc"

# ---- 5. a new row reaches get, states and live with no other edit ----
mkdir -p "$TMP/kit/lib/spec"
cp "$SS" "$TSV" "$TMP/kit/lib/spec/"
printf 'REVIEWING\tactive\tSHIPPED\tIN-REVIEW\n' >> "$TMP/kit/lib/spec/states.tsv"
f="$(spec added $'Status: in-review (round 1)\n')"
got="$(bash "$TMP/kit/lib/spec/spec-status.sh" get "$f")"
live="$(bash "$TMP/kit/lib/spec/spec-status.sh" live "$f")"
[ "$got" = REVIEWING ] && [ "$live" = "$f" ] && pass "an added row (and its alias) is read, and is live by class" || fail "added row not derived: get=$got live=$live"
mv "$TMP/kit/lib/spec/states.tsv" "$TMP/kit/lib/spec/states.tsv.off"
if out="$(bash "$TMP/kit/lib/spec/spec-status.sh" get "$f" 2>&1)"; then
  fail "spec-status ran with no states.tsv: $out"
else
  case "$out" in *FATAL*states.tsv*) pass "missing states.tsv is fatal" ;; *) fail "missing table, wrong error: $out" ;; esac
fi

# ---- 6. live: class decides, --none picks the NONE side, order kept, bad paths skipped ----
L="$TMP/live"; mkdir -p "$L"
printf 'Status: DRAFT\n'                > "$L/a.md"
printf 'Status: SHIPPED (v1)\n'         > "$L/b.md"
printf '**Status:** SUPERSEDED\n'       > "$L/c.md"
printf 'no header\n'                    > "$L/d.md"
: > "$L/e.md"
printf 'Status: MYSTERY\n'              > "$L/f.md"
ln -s /nonexistent "$L/g.md"
got="$(bash "$SS" live --none dead "$L"/*.md | xargs -n1 basename | paste -sd ' ' -)"
[ "$got" = "a.md f.md" ] && pass "live --none dead: active and unknown stay, closed and header-less go" || fail "live --none dead: $got"
got="$(bash "$SS" live --none live "$L"/*.md | xargs -n1 basename | paste -sd ' ' -)"
[ "$got" = "a.md d.md e.md f.md" ] && pass "live --none live: header-less and empty stay live; a dangling link is skipped" || fail "live --none live: $got"
got="$(bash "$SS" live "$L"/a.md "$L"/b.md | xargs -n1 basename | paste -sd ' ' -)"
[ "$got" = "a.md" ] && pass "live defaults to --none dead" || fail "live default: $got"
bash "$SS" live --none maybe "$L"/a.md >/dev/null 2>&1; rc=$?
[ "$rc" = 64 ] && pass "live --none maybe exits 64" || fail "live --none maybe rc=$rc"
[ -z "$(bash "$SS" live --none live)" ] && pass "live with no files prints nothing" || fail "live with no files printed output"

# ---- 7. every reader agrees on one fixture set ----
mkrepo() {  # mkrepo <dir>
  mkdir -p "$1/docs/specs"
  ( cd "$1" && git init -q && git checkout -q -b main ) 2>/dev/null
}
write() { printf '%s\n%s\n' "$2" "uses $3 and more" > "$1/docs/specs/$4.md"; }  # <repo> <status line> <src> <spec file>
R="$TMP/repo-a"; mkrepo "$R"
write "$R" 'Status: DRAFT' d001/f001.go SPEC-001-plain-draft
write "$R" '**Status:** VALIDATED (the change lands in the same PR)' d002/f002.go SPEC-002-bold-validated
write "$R" 'Status: Draft · 2026-07-31 · Owner: Han' d003/f003.go SPEC-003-dot-draft
write "$R" 'Status: BUILT (the code lands in this PR)' d004/f004.go SPEC-004-built
write "$R" '**Status:** SHIPPED' d005/f005.go SPEC-005-bold-shipped
write "$R" 'Status: SHIPPED-PENDING (PR #125)' d006/f006.go SPEC-006-shipped-pending
write "$R" 'Status: SUPERSEDED' d007/f007.go SPEC-007-superseded

out="$(cd "$R" && bash "$KIT_DIR/hooks/context-readiness.sh" 2>/dev/null)"
case "$out" in *"spec:ambiguous(SPEC-001,SPEC-002,SPEC-003,SPEC-004)"*) pass "context-readiness: live = 001 002 003 004 (bold, decorated and alias forms read)" ;; *) fail "context-readiness live set: $(printf '%s' "$out" | grep -o 'spec:[^ ]*' | head -1)" ;; esac

pick() {  # pick <repo> <hook> <regex>
  ( cd "$1" && echo '{"session_id":"t"}' | bash "$KIT_DIR/hooks/$2" 2>/dev/null; cat .claude/backups/*.md 2>/dev/null ) | grep -oE "$3" | head -1
}
got="$(pick "$R" pre-compact-backup.sh 'Spec: docs/specs/SPEC-[0-9]+')"
[ "$got" = "Spec: docs/specs/SPEC-004" ] && pass "pre-compact-backup: active spec = highest live (004)" || fail "pre-compact-backup picked: $got"
got="$(pick "$R" post-compact-reinject.sh 'SPEC: docs/specs/SPEC-[0-9]+')"
[ "$got" = "SPEC: docs/specs/SPEC-004" ] && pass "post-compact-reinject: active spec = highest live (004)" || fail "post-compact-reinject picked: $got"

dg() {  # dg <repo> <file>: prints the drift warning, if any
  echo "{\"tool_input\":{\"file_path\":\"$2\"}}" | ( cd "$1" && bash "$KIT_DIR/hooks/spec-drift-guard.sh" 2>/dev/null )
}
for n in f001 f002 f003 f004; do
  case "$(dg "$R" "d${n#f}/$n.go")" in *"not in any active spec"*) fail "spec-drift-guard: d${n#f}/$n.go sits in a live spec but drifted" ;; *) pass "spec-drift-guard: d${n#f}/$n.go is known (live spec)" ;; esac
done
for n in f005 f006 f007; do
  case "$(dg "$R" "d${n#f}/$n.go")" in *"not in any active spec"*) pass "spec-drift-guard: d${n#f}/$n.go drifts (closed spec)" ;; *) fail "spec-drift-guard: d${n#f}/$n.go sits in a closed spec but counted as known" ;; esac
done

# goal-drafts and spec-index
shipped_ids=""
for id in 001 002 003 004 005 006 007; do
  if ( export GOAL_SPECS_DIR="$R/docs/specs"; source "$KIT_DIR/lib/goal/goal-drafts.sh" >/dev/null 2>&1; spec_is_shipped "SPEC-$id" ); then shipped_ids="$shipped_ids $id"; fi
done
[ "$shipped_ids" = " 005 006" ] && pass "goal-drafts: shipped = 005 006 (bold and SHIPPED-PENDING read; PARKED is not shipped)" || fail "goal-drafts shipped:$shipped_ids"
idx="$(cd "$R" && bash "$KIT_DIR/lib/spec/spec-index.sh" list)"
col="$(printf '%s\n' "$idx" | awk -F' [|] ' '/SPEC-[0-9]+ [|]/ { print substr($1, match($1, /SPEC-[0-9]+/), 8) "=" $NF }' | paste -sd ' ' -)"
[ "$col" = "SPEC-001=DRAFT SPEC-002=VALIDATED SPEC-003=DRAFT SPEC-004=VALIDATED SPEC-005=SHIPPED SPEC-006=SHIPPED SPEC-007=PARKED" ] \
  && pass "spec-index: the Status column shows the canonical state for every form" || fail "spec-index column: $col"

# A single bold live spec reaches the cycle suggestion through the canonical name.
R1="$TMP/repo-one"; mkrepo "$R1"
printf '**Status:** Draft (revision 2)\n' > "$R1/docs/specs/SPEC-001-x.md"
out="$(cd "$R1" && bash "$KIT_DIR/hooks/context-readiness.sh" 2>/dev/null)"
case "$out" in *"spec:DRAFT"*"spec is DRAFT"*) pass "context-readiness: a bold decorated Draft reads as DRAFT and suggests validation" ;; *) fail "context-readiness draft: $(printf '%s' "$out" | head -c 300)" ;; esac

# ---- 7b. NONE: each reader keeps the behavior it had for a spec with no header ----
RN="$TMP/repo-none"; mkrepo "$RN"
write "$RN" 'Status: SHIPPED' da01/fa01.go SPEC-001-shipped
printf '# T\nno header, uses dfa02/fa02.go\n' > "$RN/docs/specs/SPEC-002-headerless.md"
out="$(cd "$RN" && bash "$KIT_DIR/hooks/context-readiness.sh" 2>/dev/null)"
case "$out" in *"no spec found"*) pass "context-readiness: NONE is not live" ;; *) fail "context-readiness treated a header-less spec as live" ;; esac
got="$(pick "$RN" pre-compact-backup.sh 'Spec: docs/specs/SPEC-[0-9]+')"
[ "$got" = "Spec: docs/specs/SPEC-002" ] && pass "pre-compact-backup: NONE is live" || fail "pre-compact-backup NONE: $got"
got="$(pick "$RN" post-compact-reinject.sh 'SPEC: docs/specs/SPEC-[0-9]+')"
[ "$got" = "SPEC: docs/specs/SPEC-002" ] && pass "post-compact-reinject: NONE is live" || fail "post-compact-reinject NONE: $got"
case "$(dg "$RN" dfa02/fa02.go)" in *"not in any active spec"*) fail "spec-drift-guard: NONE treated as closed" ;; *) pass "spec-drift-guard: NONE is live" ;; esac

# ---- 8. no code file hardcodes the spec vocabulary again ----
# A copy is a line naming two or more distinct spec states (or aliases) in capitals. Docs (*.md),
# tests, fixtures, the table and its reader are exempt.
vocab="$(rows | awk -F'\t' '{ printf "%s ", $1; if ($4 != "-") printf "%s ", $4 }')"
scan() {  # scan <file...>: print lines naming >= 2 distinct vocabulary words
  awk -v vocab="$vocab" '
    BEGIN { n = split(vocab, w, " ") }
    { hits = 0
      for (i = 1; i <= n; i++) if ($0 ~ ("(^|[^A-Za-z-])" w[i] "([^A-Za-z-]|$)")) hits++
      if (hits >= 2) print FILENAME ":" FNR ": " $0 }' "$@"
}
copies="$(cd "$KIT_DIR" && grep -rlIE '[A-Z]' hooks lib bin 2>/dev/null \
  | grep -v -e '\.md$' -e '^lib/spec/states.tsv$' -e '^lib/spec/spec-status.sh$' -e '/tests/' -e '/fixtures/' -e '/docs/' \
  | xargs scan 2>/dev/null)"
[ -z "$copies" ] && pass "no hardcoded copy of the spec vocabulary outside states.tsv" || fail "hardcoded vocabulary, derive it from states.tsv instead:
$copies"

# The scan must catch a planted copy (negative control on the detector itself).
plant="$TMP/plant.sh"
printf "grep -qiE '^Status:[[:space:]]*(SHIPPED|PARKED)' \"\$F\"\n" > "$plant"
[ -n "$(scan "$plant")" ] && pass "copy detector catches a planted copy" || fail "copy detector missed a planted copy"
printf '# one state alone is fine: SHIPPED\n' > "$plant"
[ -z "$(scan "$plant")" ] && pass "copy detector ignores a line with a single state" || fail "copy detector flagged a single state"

[ "$FAILED" -eq 0 ] && { echo "All spec-states tests passed."; exit 0; }
echo "$FAILED spec-states test(s) failed."; exit 1
