#!/usr/bin/env bash
# test-repohygiene.sh -- lib/repohygiene/repohygiene.sh, the Tier 1 scanner of the
# kit:repo-hygiene audit loop (SPEC-256).
#
# Every case builds a real throwaway git repo, seeds exactly the decay one detector is
# supposed to find, and runs the real scanner against it. Nothing here mocks git: the
# detectors read commit history and filesystem mtimes, and a mock would test the mock.
#
# The two contract cases matter most. The loop must never emit a deletion, and it must never
# recommend touching anything gitignored, because both failures cost data and neither is
# visible in a findings list that only gets eyeballed.
#
# Run: bash tests/test-repohygiene.sh   (exit 0 = all green)

set -uo pipefail
KIT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCAN="$KIT_DIR/lib/repohygiene/repohygiene.sh"
SKILL="$KIT_DIR/skills/repo-hygiene/SKILL.md"

PASS=0; FAIL=0; TOTAL=0
RED='\033[0;31m'; GREEN='\033[0;32m'; NC='\033[0m'
assert() { TOTAL=$((TOTAL+1)); if [ "$2" -eq 0 ]; then echo -e "  ${GREEN}PASS${NC} $1"; PASS=$((PASS+1)); else echo -e "  ${RED}FAIL${NC} $1 ${3:-}"; FAIL=$((FAIL+1)); fi; }
has() { case "$1" in *"$2"*) return 0 ;; *) return 1 ;; esac; }

TMPS=()
_mk() { local d; d="$(mktemp -d)"; TMPS+=("$d"); printf '%s' "$d"; }
cleanup() { local d; for d in "${TMPS[@]:-}"; do [ -n "$d" ] && rm -rf "$d" 2>/dev/null; done; }
trap cleanup EXIT

# A repo with a deterministic identity and no ambient config: the operator's own commit
# template or gpg signing must not decide whether this suite passes.
mkrepo() {
  local d; d="$(_mk)"
  git -C "$d" init -q 2>/dev/null
  git -C "$d" config user.email "test@example.invalid"
  git -C "$d" config user.name "Repo Hygiene Test"
  git -C "$d" config commit.gpgsign false
  printf '%s' "$d"
}
# Commit at a fixed date so an age assertion is stable a year from now.
commit_at() { GIT_AUTHOR_DATE="$2" GIT_COMMITTER_DATE="$2" git -C "$1" commit -q -m "$3"; }
scan() { bash "$SCAN" scan --repo "$1" "${@:2}" 2>&1; }

echo "=== repo-hygiene scanner (SPEC-256) ==="

# ---------------------------------------------------------------- refusal guard
echo "-- refusal guard: not a git repo --"
NOTREPO="$(_mk)"
OUT="$(scan "$NOTREPO" 2>&1)"; RC=$?
assert "a non-git target exits non-zero" $([ "$RC" -ne 0 ] && echo 0 || echo 1) "-- rc=$RC"
has "$OUT" "disk-reclaim" && R=0 || R=1
assert "the refusal names disk-reclaim as the machine-surface owner" $R "-- got: $OUT"

# The same boundary has to be stated in the shipped skill, or an agent reading only the
# skill will point this loop at a home folder.
grep -q 'disk-reclaim' "$SKILL"; assert "SKILL.md names disk-reclaim as out of scope" $?
grep -q 'REPO-SCOPED' "$SKILL"; assert "SKILL.md states the repo-scoped boundary" $?

# ---------------------------------------------------------------- detector 1
echo "-- detector 1: unreferenced doc past the age threshold --"
R1="$(mkrepo)"
mkdir -p "$R1/notes"
echo "# orphan" > "$R1/notes/orphan-note.md"
echo "# linked" > "$R1/notes/linked-note.md"
printf '# index\n\nsee notes/linked-note.md\n' > "$R1/INDEX.md"
git -C "$R1" add -A; commit_at "$R1" "2024-01-02T00:00:00" "docs: seed"
OUT="$(scan "$R1" --detectors 1 --stale-days 30)"
has "$OUT" "orphan-note.md" && R=0 || R=1
assert "flags the unreferenced note" $R "-- got: $OUT"
has "$OUT" "linked-note.md" && R=1 || R=0
assert "does not flag the referenced note" $R "-- got: $OUT"
has "$OUT" "0 hits outside itself" && R=0 || R=1
assert "evidence carries the zero-hit result" $R
has "$OUT" "git grep -I -n -E" && R=0 || R=1
assert "evidence carries the exact grep command" $R
OUT="$(scan "$R1" --detectors 1 --stale-days 99999)"
has "$OUT" "orphan-note.md" && R=1 || R=0
assert "a young file is below the age threshold and is not flagged" $R

# A basename with regex metacharacters must be searched literally, or the reference check
# silently matches the wrong thing and reports a live file as an orphan.
R1B="$(mkrepo)"
mkdir -p "$R1B/notes"
echo "x" > "$R1B/notes/report(v2).md"
printf 'see notes/report(v2).md\n' > "$R1B/INDEX.md"
git -C "$R1B" add -A; commit_at "$R1B" "2024-01-02T00:00:00" "docs: seed"
OUT="$(scan "$R1B" --detectors 1 --stale-days 30)"
has "$OUT" "report(v2)" && R=1 || R=0
assert "a basename with regex metacharacters is matched literally" $R "-- got: $OUT"

# ---------------------------------------------------------------- detector 2
echo "-- detector 2: stale staging drop, with its duplicate --"
R2="$(mkrepo)"
mkdir -p "$R2/_inbox" "$R2/docs"
echo "shared body" > "$R2/docs/absorbed.md"
echo "only here" > "$R2/README.md"
git -C "$R2" add -A; commit_at "$R2" "2024-01-02T00:00:00" "docs: seed"
echo "shared body" > "$R2/_inbox/absorbed.md"
echo "never absorbed" > "$R2/_inbox/unique-drop.md"
touch -t 202401020000 "$R2/_inbox/absorbed.md" "$R2/_inbox/unique-drop.md"
OUT="$(scan "$R2" --detectors 2)"
has "$OUT" "_inbox/absorbed.md" && R=0 || R=1
assert "flags the stale duplicate drop" $R "-- got: $OUT"
has "$OUT" "duplicate-of docs/absorbed.md" && R=0 || R=1
assert "evidence names the duplicate's path" $R
has "$OUT" "identical sha256" && R=0 || R=1
assert "evidence proves the duplicate by content hash" $R
printf '%s\n' "$OUT" | grep -q '^2	REMOVE	.*_inbox/absorbed.md'; assert "the duplicate is REMOVE (a proposal with a named successor)" $?
printf '%s\n' "$OUT" | grep -q '^2	UNSURE	.*unique-drop.md'; assert "a drop with no duplicate is UNSURE, the operator's call" $?
# Freshness is filesystem mtime, because a staging dir is normally gitignored.
touch "$R2/_inbox/unique-drop.md"
OUT="$(scan "$R2" --detectors 2)"
has "$OUT" "unique-drop.md" && R=1 || R=0
assert "a freshly touched drop drops out of the item set" $R

# ---------------------------------------------------------------- detector 3
echo "-- detector 3: record parked in a control surface --"
R3="$(mkrepo)"
mkdir -p "$R3/_meta" "$R3/tools/vps-mon" "$R3/docs/research"
echo "t" > "$R3/tools/vps-mon/README.md"
echo "r" > "$R3/README.md"
git -C "$R3" add -A; commit_at "$R3" "2024-01-02T00:00:00" "chore: seed"
echo "arch notes" > "$R3/docs/research/architecture.md"
git -C "$R3" add -A; commit_at "$R3" "2024-02-02T00:00:00" "feat(vps-mon): collector agent"
echo "log" > "$R3/_meta/LAB_LOG.md"
git -C "$R3" add -A; commit_at "$R3" "2024-02-03T00:00:00" "feat(vps-mon): log it"
OUT="$(scan "$R3" --detectors 3)"
printf '%s\n' "$OUT" | grep -q '^3	FIX	docs/research/architecture.md'; assert "flags the owned record as FIX" $?
has "$OUT" "owner tools/vps-mon" && R=0 || R=1
assert "evidence names the owner" $R "-- got: $OUT"
has "$OUT" "co-locate to tools/vps-mon/docs/research/architecture.md" && R=0 || R=1
assert "evidence names the destination path" $R
has "$OUT" "_meta/LAB_LOG.md" && R=1 || R=0
assert "the control surface's own log is never an owned record" $R "-- got: $OUT"

# One stray commit under a tool's scope must not claim a file that surface owns.
R3B="$(mkrepo)"
mkdir -p "$R3B/_meta" "$R3B/tools/vps-mon"
echo "t" > "$R3B/tools/vps-mon/README.md"; echo "r" > "$R3B/README.md"
git -C "$R3B" add -A; commit_at "$R3B" "2024-01-02T00:00:00" "chore: seed"
echo "a" > "$R3B/_meta/study-queue.md"; git -C "$R3B" add -A; commit_at "$R3B" "2024-02-01T00:00:00" "docs(notes): queue"
echo "b" >> "$R3B/_meta/study-queue.md"; git -C "$R3B" add -A; commit_at "$R3B" "2024-02-02T00:00:00" "docs(notes): more"
echo "c" >> "$R3B/_meta/study-queue.md"; git -C "$R3B" add -A; commit_at "$R3B" "2024-02-03T00:00:00" "feat(vps-mon): stray touch"
OUT="$(scan "$R3B" --detectors 3)"
has "$OUT" "study-queue.md" && R=1 || R=0
assert "a minority owner scope does not claim the file" $R "-- got: $OUT"

# ---------------------------------------------------------------- detector 4
echo "-- detector 4: log past the budget the repo documents --"
R4="$(mkrepo)"
mkdir -p "$R4/_meta"
i=0; : > "$R4/_meta/LAB_LOG.md"
while [ "$i" -lt 150 ]; do echo "2026-08-0$(( i % 9 + 1 )) - entry $i" >> "$R4/_meta/LAB_LOG.md"; i=$((i+1)); done
while [ "$i" -lt 250 ]; do echo "2026-07-0$(( i % 9 + 1 )) - entry $i" >> "$R4/_meta/LAB_LOG.md"; i=$((i+1)); done
printf 'If LAB_LOG exceeds ~200 lines or any single month occupies more than ~120 lines, run doc-compaction on it.\n' > "$R4/CLAUDE.md"
echo r > "$R4/README.md"
git -C "$R4" add -A; commit_at "$R4" "2024-01-02T00:00:00" "docs: seed"
OUT="$(scan "$R4" --detectors 4)"
printf '%s\n' "$OUT" | grep -q '^4	FIX	_meta/LAB_LOG.md'; assert "flags the over-budget log" $?
has "$OUT" "total=250 lines vs threshold 200" && R=0 || R=1
assert "evidence carries the count against the threshold" $R "-- got: $OUT"
has "$OUT" "CLAUDE.md:1" && R=0 || R=1
assert "evidence cites the threshold's source file:line" $R
has "$OUT" "busiest month 2026-08 at 150" && R=0 || R=1
assert "evidence carries the per-month count" $R
# A repo that documents no budget gets counts and an honest UNSURE, never an invented number.
R4B="$(mkrepo)"
mkdir -p "$R4B/_meta"; echo "2026-08-01 - one" > "$R4B/_meta/LAB_LOG.md"; echo r > "$R4B/README.md"
git -C "$R4B" add -A; commit_at "$R4B" "2024-01-02T00:00:00" "docs: seed"
OUT="$(scan "$R4B" --detectors 4)"
printf '%s\n' "$OUT" | grep -q '^4	UNSURE	_meta/LAB_LOG.md.*no documented threshold'; assert "no documented threshold yields UNSURE, not an invented one" $?

# ---------------------------------------------------------------- detector 5
echo "-- detector 5: large cold gitignored dir, report only --"
R5="$(mkrepo)"
mkdir -p "$R5/.venv/lib"
printf '.venv/\n' > "$R5/.gitignore"; echo r > "$R5/README.md"
git -C "$R5" add -A; commit_at "$R5" "2024-01-02T00:00:00" "chore: seed"
dd if=/dev/zero of="$R5/.venv/lib/blob.bin" bs=1024 count=2048 2>/dev/null
touch -t 202401020000 "$R5/.venv/lib/blob.bin" "$R5/.venv/lib" "$R5/.venv"
OUT="$(scan "$R5" --detectors 5 --cold-mb 1 --cold-days 30)"
printf '%s\n' "$OUT" | grep -q '^5	UNSURE	\.venv'; assert "flags the large cold ignored dir as UNSURE" $?
has "$OUT" "REPORT ONLY" && R=0 || R=1
assert "evidence is tagged REPORT ONLY" $R "-- got: $OUT"
has "$OUT" "never a deletion proposal" && R=0 || R=1
assert "evidence states it is never a deletion proposal" $R
OUT="$(scan "$R5" --detectors 5 --cold-mb 9999 --cold-days 30)"
has "$OUT" ".venv" && R=1 || R=0
assert "a dir under the size threshold is not flagged" $R
touch "$R5/.venv/lib/blob.bin"
OUT="$(scan "$R5" --detectors 5 --cold-mb 1 --cold-days 30)"
has "$OUT" ".venv" && R=1 || R=0
assert "a warm dir is not flagged" $R

# ---------------------------------------------------------------- contract
echo "-- contract: the loop surfaces, it never deletes --"
# Every detector, one repo, all decay classes at once: no output line may carry a delete verb
# or the REMOVE verdict outside detector 2, and no line may propose acting on an ignored path.
touch -t 202401020000 "$R5/.venv/lib/blob.bin"   # the warm-dir case above left it fresh
OUT="$(scan "$R2" --detectors 1,2,3,4,5 --stale-days 1 --cold-mb 1)$(scan "$R5" --detectors 1,2,3,4,5 --stale-days 1 --cold-mb 1)"
printf '%s\n' "$OUT" | grep -q '^5	'; assert "the contract run actually produced a detector-5 finding to judge" $?
printf '%s\n' "$OUT" | grep -qE '(^|[^a-z])(rm -rf|rm -f|git rm|unlink |trash )'; R=$?
assert "no scan output contains a deletion command" $([ "$R" -ne 0 ] && echo 0 || echo 1)
# The scanner cleans up its OWN mktemp dir; every other deletion verb is a defect.
STRAY=$(grep -nE '(^|[^a-z])(rm |git rm|unlink )' "$SCAN" | grep -v 'TMP' | wc -l | tr -d ' ')
assert "the scanner source has no deletion verb outside its own temp dir ($STRAY stray)" $([ "$STRAY" = "0" ] && echo 0 || echo 1) \
  "-- $(grep -nE '(^|[^a-z])(rm |git rm|unlink )' "$SCAN" | grep -v 'TMP')"
printf '%s\n' "$OUT" | grep '^5	' | grep -qv 'UNSURE'; R=$?
assert "every detector-5 finding is UNSURE, never FIX or REMOVE" $([ "$R" -ne 0 ] && echo 0 || echo 1)

# Every emitted finding carries evidence. An evidence-less row is the failure mode this
# instance exists to prevent, so it is a test, not a convention.
BAD=$(printf '%s\n' "$OUT" | awk -F'\t' '$1 ~ /^[1-5]$/ && (NF < 4 || length($4) < 20)' | wc -l | tr -d ' ')
assert "every finding carries a non-trivial evidence field ($BAD bare rows)" $([ "$BAD" = "0" ] && echo 0 || echo 1)

# ---------------------------------------------------------------- wiring
echo "-- wiring: registration surfaces --"
grep -q 'kit:audit-scanner' "$SKILL"; assert "SKILL.md dispatches kit:audit-scanner for Tier 2" $?
grep -q 'general-purpose subagent' "$SKILL"; assert "SKILL.md names the general-purpose fallback" $?
grep -q 'repo-hygiene' "$KIT_DIR/agents/audit-scanner.md"; assert "audit-scanner names repo-hygiene as a dispatching instance" $?
grep -q 'repo-hygiene' "$KIT_DIR/docs/patterns/audit-loop.md"; assert "the pattern doc lists repo-hygiene under Known instances" $?
grep -q '| repo-hygiene |' "$KIT_DIR/README.md"; assert "README skills table carries a repo-hygiene row" $?

echo
echo "$PASS/$TOTAL passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
