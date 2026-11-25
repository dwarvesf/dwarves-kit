#!/usr/bin/env bash
# test-check-owners.sh - run check-owners.sh against throwaway git repos. No network.
# Each case builds a small repo with a copy of the script, an OWNERS.md and some tracked files.
# Leaves its temp dir behind; the path is printed.
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SCRIPT="$HERE/check-owners.sh"
T="$(mktemp -d "${TMPDIR:-/tmp}/check-owners-test.XXXXXX")"
echo "test dir: $T"

fails=0
ok() { echo "PASS  $1"; }
bad() { echo "FAIL  $1"; fails=$((fails + 1)); }
expect() { # expect <label> <condition command...>
    local label="$1"
    shift
    if "$@" >/dev/null 2>&1; then ok "$label"; else bad "$label"; fi
}

mkrepo() { # mkrepo: a fresh repo with the script tracked; prints its path
    local r
    r="$(mktemp -d "$T/repo.XXXXXX")"
    mkdir -p "$r/scripts" "$r/.github/workflows"
    git -C "$r" init -q 2>/dev/null
    cp "$SCRIPT" "$r/scripts/check-owners.sh"
    printf '%s\n' '#!/usr/bin/env bash' 'echo build' >"$r/scripts/build.sh"
    printf '%s\n' 'name: ci' >"$r/.github/workflows/ci.yml"
    printf '%s\n' '# a product file, not tracked by the check' >"$r/README.md"
    git -C "$r" add -A 2>/dev/null
    echo "$r"
}
HEAD_ROWS='# Owners

## Rule

- Every script and workflow has one owner.

## Scripts and workflows

| Path | What it does | Owner | Sponsor |
|---|---|---|---|'
FULL_ROWS='| `scripts/check-owners.sh` | Owners check | @alice | |
| `scripts/build.sh` | Build | @alice | |
| `.github/workflows/ci.yml` | CI | @alice | |'
write_owners() { # write_owners <repo> [rows...]: header plus the given rows
    local r="$1"
    shift
    { printf '%s\n' "$HEAD_ROWS"; [ "$#" -eq 0 ] || printf '%s\n' "$@"; } >"$r/OWNERS.md"
}
run() { # run <repo> <name>: stdout in $T/<name>, stderr in $T/<name>.err, exit in $rc
    rc=0
    (cd "$1" && bash scripts/check-owners.sh) >"$T/$2" 2>"$T/$2.err" || rc=$?
}
has() { grep -Fq -- "$2" "$T/$1"; }
# pairs_ok <name>: stderr is an even number of lines, each odd line starts "check-owners: ", each even "Fix: "
pairs_ok() {
    awk 'NR % 2 == 1 && $0 !~ /^check-owners: / { exit 1 } NR % 2 == 0 && $0 !~ /^Fix: / { exit 1 } END { exit (NR == 0 || NR % 2 != 0) }' "$T/$1.err"
}
lines_of() { wc -l <"$T/$1" | tr -d ' '; }

# 1. a complete table passes
r="$(mkrepo)"
write_owners "$r" "$FULL_ROWS"
run "$r" full
expect "complete table: exit 0" [ "$rc" -eq 0 ]
expect "complete table: reports the count" has full "check-owners: 3 paths, all owned"
expect "complete table: stderr empty" [ ! -s "$T/full.err" ]

# 2. a tracked script with no row
r="$(mkrepo)"
printf '%s\n' '#!/usr/bin/env bash' >"$r/scripts/new-thing.sh"
git -C "$r" add -A
write_owners "$r" "$FULL_ROWS"
run "$r" norow
expect "script with no row: exit 1" [ "$rc" -eq 1 ]
expect "script with no row: names it" has norow.err "check-owners: no owner yet for scripts/new-thing.sh"
expect "script with no row: exactly two lines" [ "$(lines_of norow.err)" -eq 2 ]
expect "script with no row: rule then Fix" pairs_ok norow
fixline="$(grep '^Fix: ' "$T/norow.err" | sed 's/^Fix: //')"
(cd "$r" && bash -c "$fixline")
run "$r" norow2
expect "script with no row: the Fix line, pasted, makes the check pass" [ "$rc" -eq 0 ]

# 3. a workflow with no row
r="$(mkrepo)"
printf '%s\n' 'name: nightly' >"$r/.github/workflows/nightly.yml"
git -C "$r" add -A
write_owners "$r" "$FULL_ROWS"
run "$r" nowf
expect "workflow with no row: exit 1" [ "$rc" -eq 1 ]
expect "workflow with no row: names it" has nowf.err ".github/workflows/nightly.yml"

# 4. a repo's own script that predates OWNERS.md refuses too
r="$(mkrepo)"
printf '%s\n' '#!/usr/bin/env bash' >"$r/scripts/legacy-deploy.sh"
git -C "$r" add -A
write_owners "$r" "$FULL_ROWS"
run "$r" legacy
expect "pre-existing script: refused as no owner yet" has legacy.err "no owner yet for scripts/legacy-deploy.sh"

# 5. a row that points at a missing path
r="$(mkrepo)"
write_owners "$r" "$FULL_ROWS" '| `scripts/gone.sh` | Was removed | @alice | |'
run "$r" dead
expect "dead row: exit 1" [ "$rc" -eq 1 ]
expect "dead row: names the path" has dead.err "row names a path that does not exist: scripts/gone.sh"
expect "dead row: rule then Fix" pairs_ok dead
fixline="$(grep '^Fix: ' "$T/dead.err" | sed 's/^Fix: //')"
(cd "$r" && bash -c "$fixline")
run "$r" dead2
expect "dead row: the Fix line, pasted, makes the check pass" [ "$rc" -eq 0 ]

# 6. an empty owner
r="$(mkrepo)"
write_owners "$r" '| `scripts/check-owners.sh` | Owners check | @alice | |' '| `scripts/build.sh` | Build | | |' '| `.github/workflows/ci.yml` | CI | @alice | |'
run "$r" noowner
expect "empty owner: exit 1" [ "$rc" -eq 1 ]
expect "empty owner: names the row" has noowner.err "empty owner: scripts/build.sh"
expect "empty owner: rule then Fix" pairs_ok noowner

# 7. an agent owner needs a sponsor
r="$(mkrepo)"
write_owners "$r" '| `scripts/check-owners.sh` | Owners check | @alice | |' '| `scripts/build.sh` | Build | build-agent | |' '| `.github/workflows/ci.yml` | CI | @alice | |'
run "$r" nosponsor
expect "agent owner, no sponsor: exit 1" [ "$rc" -eq 1 ]
expect "agent owner, no sponsor: names the owner" has nosponsor.err "agent owner 'build-agent' has no sponsor"
expect "agent owner, no sponsor: rule then Fix" pairs_ok nosponsor
write_owners "$r" '| `scripts/check-owners.sh` | Owners check | @alice | |' '| `scripts/build.sh` | Build | build-agent | @alice |' '| `.github/workflows/ci.yml` | CI | @alice | |'
run "$r" sponsor
expect "agent owner with a sponsor: exit 0" [ "$rc" -eq 0 ]

# 8. several offenders: one pair each
r="$(mkrepo)"
write_owners "$r" '| `scripts/check-owners.sh` | Owners check | | |' '| `scripts/gone.sh` | Gone | @alice | |'
run "$r" many
expect "several offenders: four lines (build.sh and ci.yml unowned, empty owner, dead row)" [ "$(lines_of many.err)" -eq 8 ]
expect "several offenders: every line pairs" pairs_ok many

# 9. a job with no file: owner and sponsor are checked, the path is not
r="$(mkrepo)"
write_owners "$r" "$FULL_ROWS" '| nightly-backup | Cron job on the build host | @alice | |'
run "$r" job
expect "job row with an owner: exit 0" [ "$rc" -eq 0 ]
write_owners "$r" "$FULL_ROWS" '| nightly-backup | Cron job on the build host | | |'
run "$r" job2
expect "job row with no owner: exit 1" [ "$rc" -eq 1 ]
expect "job row with no owner: names the job" has job2.err "empty owner: nightly-backup"

# 10. rows are read from a second table and from CRLF files
r="$(mkrepo)"
{ printf '%s\n' "$HEAD_ROWS" "$FULL_ROWS" '' '## Jobs' '' '| Name | Where | Owner | Sponsor |' '|---|---|---|---|' '| report | cron | @alice | |'; } | sed 's/$/\r/' >"$r/OWNERS.md"
run "$r" crlf
expect "CRLF file with a second table: exit 0" [ "$rc" -eq 0 ]

# 11. no OWNERS.md, and not a git repo
r="$(mkrepo)"
run "$r" noowners
expect "no OWNERS.md: exit 1" [ "$rc" -eq 1 ]
expect "no OWNERS.md: says so, rule then Fix" pairs_ok noowners
expect "no OWNERS.md: names the file" has noowners.err "OWNERS.md is missing"
mkdir -p "$T/nogit/scripts"
cp "$SCRIPT" "$T/nogit/scripts/check-owners.sh"
rc=0
(cd "$T/nogit" && bash scripts/check-owners.sh) >"$T/nogit.out" 2>"$T/nogit.out.err" || rc=$?
expect "not a git repo: exit 1" [ "$rc" -eq 1 ]
expect "not a git repo: rule then Fix" pairs_ok nogit.out

# 12. an untracked script is not required to have a row
r="$(mkrepo)"
printf '%s\n' '#!/usr/bin/env bash' >"$r/scripts/scratch.sh"
write_owners "$r" "$FULL_ROWS"
run "$r" untracked
expect "untracked file: exit 0" [ "$rc" -eq 0 ]

echo "failures: $fails"
[ "$fails" -eq 0 ]
