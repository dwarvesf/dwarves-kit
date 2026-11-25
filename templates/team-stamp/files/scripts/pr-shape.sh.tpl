#!/usr/bin/env bash
# pr-shape.sh - check the shape of one pull request. CI runs it (job pr-shape) and so does
# scripts/check.sh, with the same inputs.
#
# Inputs, all read as data (never evaluated, never used as a format string or a pattern):
#   PR_TITLE       required. The pull request title.
#   PR_BODY        the pull request body, CRLF or LF line ends. Default empty.
#   PR_BODY_FILE   a file that holds the body; used instead of PR_BODY when set.
#   BASE_SHA       the base revision. Default origin/{{DEFAULT_BRANCH}}.
#   HEAD_SHA       the head revision. Default HEAD.
# The diff is BASE_SHA...HEAD_SHA (the changes since the merge base). CI passes the four values
# from the pull request event through env: entries, with no token and no gh call; a local run
# passes the same four. Files are read from HEAD_SHA, never from the working tree.
#
#   PR_TITLE='feat(x): y' PR_BODY='Closes #12' BASE_SHA=<base> HEAD_SHA=<head> bash scripts/pr-shape.sh
#
# Output: "ok    <check>: ..." lines and detail lines on stdout; every failed check prints exactly
# two lines on stderr, "pr-shape: <the rule>" then "Fix: <what to do>". All failed checks print in
# one run. A last stdout line "checks: N failed" ends the run. Exit 0 when none failed, 1 when
# one or more failed, 2 for bad inputs (also a two-line refusal).
#
# Checks:
#   1. title      a conventional commit subject on one line, 72 characters or less
#   2. proof      a behavior path changed (any changed file that is not documentation), so the PR
#                 adds or changes a proof file docs/verification/<slug>.md (not a README) with a
#                 NEGATIVE CONTROL block: an Output: label followed by a non-empty line, an Exit:
#                 line with a non-zero code, and a line that starts Verdict: RED, in that block.
#                 Or a body line "no-proof: <reason of 10+ characters>"
#   3. board      a behavior path changed, so one of: the body has a line "Closes #<n>" (Fixes and
#                 Resolves count too; a bare mention like #12 does not); the board file
#                 ({{BOARD_FILE}}, when one is set) changed; or a body line
#                 "no-board-row: <reason of 10+ characters>"
#   4. changelog  every entry line the PR adds under "## [Unreleased]" in CHANGELOG.md starts with
#                 a tag ({{TAGS_COLON}}); a change under a product path adds at least one such
#                 line, or the body has "no-changelog: <reason of 10+ characters>"
#   5. lint       severity warning on changed shell files (a .sh file or a shell shebang), by the tool
#                 named shellcheck; with none on PATH the check is skipped with a notice, and
#                 it fails when CI=true
#   6. parity     AGENTS.md and docs/TEAM-WORKFLOW.md change together, and every AGENTS.md
#                 heading has a link [Heading](../AGENTS.md#anchor) in docs/TEAM-WORKFLOW.md.
#   7. case       no two paths of the head tree differ only in case (the merge guard and the owners
#                 check compare paths in lower case)
#                 A body line "no-rule-mirror: <reason of 10+ characters>" waives it
# A reason line starts at the first column of a body line. A reason that is a placeholder in
# angle brackets does not count.
#
# Safety: a title, body, file name, heading or changelog line is attacker-chosen text. A value
# reaches a rule line, a detail line or an ok line only through clean() (every character outside
# letters, digits and ._/@- and space becomes ?), and reaches a Fix line only when safe_arg()
# accepts it; otherwise the Fix line is a plain instruction. bash 3.2 safe.
set -uo pipefail

TAGS_ERE='{{TAGS_ERE}}'
TAGS_COLON='{{TAGS_COLON}}'
PRODUCT_ERE='{{PRODUCT_ERE}}'
BOARD_FILE='{{BOARD_FILE}}'
DEFAULT_BRANCH='{{DEFAULT_BRANCH}}'

clean() { printf '%s' "${1:0:80}" | LC_ALL=C tr -c 'A-Za-z0-9._/@ -' '?'; }
safe_re='^[A-Za-z0-9._/@-]+$'
safe_arg() { case "$1" in -* | "") return 1 ;; esac; [[ "$1" =~ $safe_re ]]; }

fails=0
passed=0
ok() {
    passed=$((passed + 1))
    printf 'ok    %s\n' "$1"
}
detail() { printf '  | %s\n' "$(clean "$1")"; }
# refuse <rule> <fix>: the two-line refusal. Control characters are dropped from both lines.
refuse() {
    local rule fix
    rule="$(printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177')"
    fix="$(printf '%s' "$2" | LC_ALL=C tr -d '\000-\037\177')"
    printf 'pr-shape: %s\nFix: %s\n' "$rule" "$fix" >&2
    fails=$((fails + 1))
}
die() {
    printf 'pr-shape: %s\nFix: %s\n' "$1" "$2" >&2
    exit 2
}

work=""
cleanup() {
    case "$work" in
    */pr-shape.*) rm -rf "$work" ;;
    esac
}
trap cleanup EXIT

# ---- inputs
if [ "${PR_TITLE+set}" != set ]; then
    die "PR_TITLE is not set, so there is no title to check" "PR_TITLE='feat(x): y' BASE_SHA='<base>' HEAD_SHA='<head>' bash scripts/pr-shape.sh"
fi
title="$PR_TITLE"
body="${PR_BODY-}"
if [ -n "${PR_BODY_FILE-}" ]; then
    [ -r "$PR_BODY_FILE" ] || die "PR_BODY_FILE is set but is not a readable file" "unset PR_BODY_FILE or point it at the body text"
    body="$(cat "$PR_BODY_FILE")"
fi
body_clean="$(printf '%s' "$body" | tr -d '\r')"

resolve() { # resolve <rev>: the commit id, or fail
    case "$1" in -* | "") return 1 ;; esac
    git rev-parse --verify -q "$1^{commit}" 2>/dev/null
}
base_ref="${BASE_SHA:-origin/$DEFAULT_BRANCH}"
head_ref="${HEAD_SHA:-HEAD}"
base_sha="$(resolve "$base_ref")" || die "the base revision $(clean "$base_ref") does not resolve in this clone" "git fetch origin # then set BASE_SHA to the base commit"
head_sha="$(resolve "$head_ref")" || die "the head revision $(clean "$head_ref") does not resolve in this clone" "git status --short # then set HEAD_SHA to the head commit"

work="$(mktemp -d "${TMPDIR:-/tmp}/pr-shape.XXXXXX")" || die "cannot make a temp directory" "export TMPDIR=<a writable directory>"
range="$base_sha...$head_sha"
if ! git -c core.quotepath=off diff --name-status -M -z "$range" >"$work/ns" 2>"$work/ns.err"; then
    die "git diff $range failed: $(clean "$(head -n 1 "$work/ns.err")")" "git fetch --unshallow # the clone needs the history between base and head"
fi

# ---- classify the changed paths
# nondoc_paths: stdin paths minus the documentation: a .md, .txt or .markdown file, and under
# docs/ an image, PDF, CSV, rst or adoc file. A path that looks like a secret is never a doc.
nondoc_paths() {
    awk '{ lc = tolower($0) }
        $0 == "" { next }
        lc ~ /(^|\/)[^\/]*credentials?[^\/]*$|(^|\/)secrets?\/|\.(pem|key|p12|pfx)$|(^|\/)\.env/ { print; next }
        $0 ~ /\.(md|txt|markdown)$/ { next }
        $0 ~ /^docs\// && $0 ~ /\.(rst|adoc|png|jpe?g|gif|webp|svg|pdf|csv)$/ { next }
        { print }'
}
is_product() { printf '%s\n' "$1" | grep -Eq "$PRODUCT_ERE"; }

all_paths="" proof_files="" shell_files=""
product=0 board_changed=0 changelog_changed=0 agents_changed=0 wf_changed=0 odd_path=0
while IFS= read -r -d '' status; do
    p1="" p2=""
    IFS= read -r -d '' p1
    case "$status" in R* | C*) IFS= read -r -d '' p2 ;; esac
    path="${p2:-$p1}"
    case "$p1$p2" in
    *$'\n'*)
        # A path with a newline cannot ride a line list: count it as product behavior.
        odd_path=1
        product=1
        continue
        ;;
    esac
    all_paths="${all_paths}${p1}
${path}
"
    if is_product "$p1" || is_product "$path"; then product=1; fi
    if [ "$p1" = AGENTS.md ] || [ "$path" = AGENTS.md ]; then agents_changed=1; fi
    if [ "$p1" = docs/TEAM-WORKFLOW.md ] || [ "$path" = docs/TEAM-WORKFLOW.md ]; then wf_changed=1; fi
    case "$status" in D*) continue ;; esac
    case "$path" in
    docs/verification/README.md | docs/verification/*/README.md) ;;
    docs/verification/*.md) proof_files="${proof_files}${path}
" ;;
    CHANGELOG.md) changelog_changed=1 ;;
    esac
    if [ -n "$BOARD_FILE" ] && [ "$path" = "$BOARD_FILE" ]; then board_changed=1; fi
    first="$(git show "$head_sha:$path" 2>/dev/null | head -n 1)"
    case "$path" in
    *.sh) shell_files="${shell_files}${path}
" ;;
    *)
        if printf '%s' "$first" | grep -Eq '^#![[:space:]]*([^ ]*/)?(env +)?(ba)?sh([[:space:]]|$)'; then
            shell_files="${shell_files}${path}
"
        fi
        ;;
    esac
done <"$work/ns"
behavior=0
if [ "$odd_path" -eq 1 ] || [ -n "$(printf '%s' "$all_paths" | nondoc_paths)" ]; then behavior=1; fi

# marker_ok <name>: true when a body line starts "<name>:" and holds a reason of 10+ characters.
# The reason is left in marker_reason.
marker_reason=""
marker_ok() {
    local line r
    marker_reason=""
    while IFS= read -r line; do
        case "$line" in
        "$1":*)
            r="${line#"$1":}"
            r="${r#"${r%%[![:space:]]*}"}"
            r="${r%"${r##*[![:space:]]}"}"
            case "$r" in "<"*">") continue ;; esac
            if [ "${#r}" -ge 10 ]; then
                marker_reason="$r"
                return 0
            fi
            ;;
        esac
    done <<<"$body_clean"
    return 1
}

# ---- 1. title
title_re='^(feat|fix|refactor|docs|test|chore|ci|build|perf)(\([a-z0-9._/-]+\))?: .+'
title_ok=0
case "$title" in
*$'\n'* | *$'\r'*) ;;
*) if [[ "$title" =~ $title_re ]] && [ "${#title}" -le 72 ]; then title_ok=1; fi ;;
esac
if [ "$title_ok" -eq 1 ]; then
    ok "title: a conventional commit subject"
else
    refuse "title is not one line of type(scope): subject with a known type (feat fix refactor docs test chore ci build perf) and 72 characters or less (${#title} now)" \
        "gh pr edit <number> --title 'fix(scripts): short subject'"
fi

# ---- 2. proof
# proof_missing <path>: what the proof file lacks, one phrase per line; nothing when it is a proof.
proof_missing() {
    git show "$head_sha:$1" 2>/dev/null | tr -d '\r' | awk '
        {
            line = $0
            if (prevout && st && line ~ /[^[:space:]]/) out = 1
            prevout = (line ~ /^[[:space:]]*Output:/)
            if (tolower(line) ~ /negative control/) { seen = 1; if (!st) { st = 1; ex = 0; out = 0 } }
            if (st && line ~ /^[[:space:]]*Exit:[[:space:]]*[1-9][0-9]*/) ex = 1
            if (st && line ~ /^[[:space:]]*Verdict:/) {
                if (line ~ /^[[:space:]]*Verdict: RED/) {
                    red = 1
                    if (ex && out) good = 1; else { lastex = ex; lastout = out }
                    st = 0
                } else { ex = 0; out = 0 }
            }
        }
        END {
            if (good) exit 0
            if (!seen) print "the words NEGATIVE CONTROL"
            else if (!red) print "a line that starts Verdict: RED after the NEGATIVE CONTROL heading"
            else {
                if (!lastex) print "an Exit: line with a non-zero code inside the NEGATIVE CONTROL block"
                if (!lastout) print "an Output: line followed by a non-empty line inside the NEGATIVE CONTROL block"
            }
            exit 1
        }'
}
negctl_fix='bash scripts/negctl.sh "<test command>" "<command that breaks one thing>" # paste its block into docs/verification/<slug>.md, or put the body line no-proof: <reason, 10+ characters>'
if [ "$behavior" -eq 0 ]; then
    ok "proof: no behavior path changed"
elif marker_ok no-proof; then
    ok "proof: skipped by the body line no-proof: $(clean "$marker_reason")"
elif [ -z "$proof_files" ]; then
    refuse "a behavior path changed and the PR adds or changes no proof file docs/verification/<slug>.md (a README is not one)" "$negctl_fix"
else
    proof_good=""
    proof_report=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        miss="$(proof_missing "$f")" && {
            proof_good="$f"
            break
        }
        proof_report="${proof_report}$(clean "$f") lacks $(printf '%s' "$miss" | paste -sd, - | sed 's/,/, /g'). "
    done <<EOF
$proof_files
EOF
    if [ -n "$proof_good" ]; then
        ok "proof: $(clean "$proof_good") holds a NEGATIVE CONTROL block with Verdict: RED"
    else
        refuse "no proof file in this PR holds a valid NEGATIVE CONTROL block: ${proof_report% }" "$negctl_fix"
    fi
fi

# ---- 3. board link
closes=0
if grep -Eiq '^(closes|fixes|resolves) #[0-9]+' <<<"$body_clean"; then closes=1; fi
if [ "$behavior" -eq 0 ]; then
    ok "board: no behavior path changed"
elif [ "$closes" -eq 1 ]; then
    ok "board: the body has a Closes #<n> line"
elif [ "$board_changed" -eq 1 ]; then
    ok "board: the board file changed"
elif marker_ok no-board-row; then
    ok "board: no-board-row line with a reason"
else
    if [ -n "$BOARD_FILE" ]; then
        refuse "a behavior path changed and nothing links the PR to its work: no Closes #<n> line in the body, $BOARD_FILE unchanged, no no-board-row: line (a bare mention like #12 is not a close)" \
            "add the body line 'Closes #<n>' for the issue that holds the work, or update the row in $BOARD_FILE, or add the body line 'no-board-row: <reason, 10+ characters>'"
    else
        refuse "a behavior path changed and nothing links the PR to its work: no Closes #<n> line in the body and no no-board-row: line (a bare mention like #12 is not a close)" \
            "add the body line 'Closes #<n>' for the issue that holds the work, or the body line 'no-board-row: <reason, 10+ characters>'"
    fi
fi

# ---- 4. changelog. Only the lines this PR adds under [Unreleased] are read.
tag_re="^[-*] ($TAGS_ERE):( |\$)"
cl_untagged=0
cl_tagged=0
cl_detail=""
if [ "$changelog_changed" -eq 1 ]; then
    added_nums="$(git diff -U0 --no-color --no-ext-diff "$range" -- CHANGELOG.md 2>/dev/null |
        awk '/^@@ / { s = $3; sub(/^\+/, "", s); n = split(s, p, ","); first = p[1] + 0; cnt = (n > 1 ? p[2] + 0 : 1); for (i = 0; i < cnt; i++) print first + i }' | tr '\n' ',')"
    while IFS=$'\t' read -r kind num text; do
        case "$kind" in
        T) cl_tagged=$((cl_tagged + 1)) ;;
        U)
            cl_untagged=$((cl_untagged + 1))
            if [ "$cl_untagged" -le 5 ]; then cl_detail="${cl_detail}line $num: $text
"; fi
            ;;
        esac
    done <<EOF
$(git show "$head_sha:CHANGELOG.md" 2>/dev/null | tr -d '\r' |
        awk -v nums="$added_nums" -v re="$tag_re" '
            BEGIN { n = split(nums, a, ","); for (i = 1; i <= n; i++) if (a[i] != "") add[a[i]] = 1 }
            /^## / { unrel = ($0 ~ /^## \[Unreleased\]/); next }
            unrel && (NR in add) && /^[-*] / {
                if ($0 ~ re) print "T\t" NR; else print "U\t" NR "\t" substr($0, 1, 80)
            }')
EOF
fi
if [ "$cl_untagged" -gt 0 ]; then
    refuse "$cl_untagged entry line(s) added under [Unreleased] in CHANGELOG.md do not start with a tag ($TAGS_COLON)" \
        "start each added line under ## [Unreleased] in CHANGELOG.md with one of: $TAGS_COLON"
    while IFS= read -r l; do
        [ -n "$l" ] && detail "$l"
    done <<EOF
$cl_detail
EOF
elif [ "$product" -eq 0 ]; then
    ok "changelog: no product path changed"
elif [ "$cl_tagged" -gt 0 ]; then
    ok "changelog: the PR adds a tagged line under [Unreleased]"
elif marker_ok no-changelog; then
    ok "changelog: no-changelog line with a reason"
else
    refuse "a product path ($PRODUCT_ERE) changed and the PR adds no tagged line under [Unreleased] in CHANGELOG.md" \
        "add a line under ## [Unreleased] in CHANGELOG.md that starts with one of: $TAGS_COLON, or add the body line 'no-changelog: <reason, 10+ characters>'"
fi

# ---- 5. shellcheck on the changed shell files, read from the head revision
if [ -z "$shell_files" ]; then
    ok "shellcheck: no shell file changed"
elif ! command -v shellcheck >/dev/null 2>&1; then
    if [ "${CI-}" = "true" ]; then
        refuse "shellcheck is not installed on this runner and shell files changed" \
            "add the shellcheck install step to the workflow job pr-shape, before the pr-shape step"
    else
        ok "shellcheck: skipped, shellcheck is not installed here (CI fails this case)"
    fi
else
    lintdir="$work/lint"
    mkdir -p "$lintdir"
    count=0
    bad_names=""
    bad_count=0
    first_bad=""
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        count=$((count + 1))
        git show "$head_sha:$f" >"$lintdir/f$count.sh" 2>/dev/null
        shell_opt=()
        if ! head -n 1 "$lintdir/f$count.sh" | grep -q '^#!'; then shell_opt=(-s bash); fi
        if ! out="$(cd "$lintdir" && shellcheck -S warning -f gcc ${shell_opt[@]+"${shell_opt[@]}"} -- "f$count.sh" 2>&1)"; then
            bad_count=$((bad_count + 1))
            [ -n "$first_bad" ] || first_bad="$f"
            if [ "$bad_count" -le 5 ]; then bad_names="${bad_names}$(clean "$f"), "; fi
            while IFS= read -r l; do
                [ -n "$l" ] || continue
                detail "$(clean "$f") $l"
            done <<EOF
$(printf '%s\n' "$out" | sed -n 's/^[^:]*:\([0-9][0-9]*\):[0-9][0-9]*: .*\[\(SC[0-9][0-9]*\)\]$/line \1 \2/p' | head -n 6)
EOF
        fi
    done <<EOF
$shell_files
EOF
    if [ "$bad_count" -eq 0 ]; then
        ok "shellcheck: $count shell file(s) clean at severity warning"
    elif safe_arg "$first_bad"; then
        refuse "shellcheck finds warnings in $bad_count changed shell file(s): ${bad_names%, }" \
            "shellcheck -S warning $first_bad # fix each finding, then run it on the other files named above"
    else
        refuse "shellcheck finds warnings in $bad_count changed shell file(s): ${bad_names%, }" \
            "run shellcheck -S warning on each changed shell file and fix each finding"
    fi
fi

# ---- 6. rule parity
headings() { # headings <rev>: every AGENTS.md heading outside a code fence, one per line
    git show "$1:AGENTS.md" 2>/dev/null | tr -d '\r' |
        awk '/^```/ { f = !f; next } !f && /^#+ / { sub(/^#+ +/, ""); sub(/ +$/, ""); print }'
}
slug() { printf '%s' "$1" | tr 'A-Z' 'a-z' | LC_ALL=C tr -cd 'a-z0-9 -' | tr ' ' '-'; }
has_both=0
if git cat-file -e "$head_sha:AGENTS.md" 2>/dev/null && git cat-file -e "$head_sha:docs/TEAM-WORKFLOW.md" 2>/dev/null; then has_both=1; fi
mirror_fix="change both files in this PR, or add the body line 'no-rule-mirror: <reason, 10+ characters>'"
if [ "$agents_changed" -eq 0 ] && [ "$wf_changed" -eq 0 ]; then
    ok "parity: neither rule file changed"
elif marker_ok no-rule-mirror; then
    ok "parity: skipped by the body line no-rule-mirror"
elif [ "$has_both" -eq 0 ]; then
    ok "parity: one of the two rule files is absent, nothing to compare"
elif [ "$agents_changed" -ne "$wf_changed" ]; then
    if [ "$agents_changed" -eq 1 ]; then
        refuse "AGENTS.md changed and docs/TEAM-WORKFLOW.md did not; the two files stay in step" "$mirror_fix"
    else
        refuse "docs/TEAM-WORKFLOW.md changed and AGENTS.md did not; the two files stay in step" "$mirror_fix"
    fi
else
    wf_text="$(git show "$head_sha:docs/TEAM-WORKFLOW.md" 2>/dev/null | tr -d '\r')"
    nolink=0
    nolink_slugs=""
    while IFS= read -r h; do
        [ -n "$h" ] || continue
        s="$(slug "$h")"
        if ! grep -qF -- "[$h](../AGENTS.md#$s)" <<<"$wf_text"; then
            nolink=$((nolink + 1))
            if [ "$nolink" -le 5 ]; then nolink_slugs="${nolink_slugs}${s:-empty}, "; fi
        fi
    done <<EOF
$(headings "$head_sha")
EOF
    if [ "$nolink" -eq 0 ]; then
        ok "parity: both rule files changed and every AGENTS.md heading has its link"
    else
        refuse "$nolink AGENTS.md heading(s) have no link in docs/TEAM-WORKFLOW.md, anchors: ${nolink_slugs%, }" \
            "add a line [Heading text](../AGENTS.md#anchor) to docs/TEAM-WORKFLOW.md for each anchor named above"
    fi
fi

# ---- 7. no two paths that differ only in case. The merge guard and the owners check compare paths in
# lower case, and a case-insensitive checkout (macOS, Windows) can write one over the other.
collide="$(git ls-tree -r --name-only -z "$head_sha" 2>/dev/null | tr '\0' '\n' | awk '{ k = tolower($0); if (k in seen) { if (n++ < 3) printf "%s ", $0 } else seen[k] = 1 } END { exit 0 }')"
if [ -z "$collide" ]; then
    ok "case: no two paths differ only in case"
else
    refuse "two paths differ only in case, so one can overwrite the other on a case-insensitive checkout: $(clean "${collide% }")" \
        "git mv <one of the paths> <a name that differs in more than case>"
fi

printf 'checks: %s failed, %s passed\n' "$fails" "$passed"
[ "$fails" -eq 0 ]
