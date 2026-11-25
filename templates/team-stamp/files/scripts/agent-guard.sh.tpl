#!/usr/bin/env bash
# agent-guard.sh - Claude Code PreToolUse hook for the Bash tool. It stops three
# wrong actions at the moment they happen and says what to do instead.
#
#   1. a bare `gh pr merge` (or the merge API) -> merge with scripts/pr-merge.sh
#   2. a push that lands on {{DEFAULT_BRANCH}}  -> push a branch and open a PR
#   3. `git commit` while on {{DEFAULT_BRANCH}} -> create a branch first
#
# Wired in .claude/settings.json. Claude Code sends the hook JSON on stdin
# (tool_input.command, cwd); exit 2 blocks and shows stderr to the agent, and any
# other exit lets the command run. A block prints exactly two lines: the rule,
# then `Fix:` with a command. Every internal failure exits 0, so a bug in this
# file never traps a session.
#
# JSON is read with jq. Without jq the guard is off: it prints one note and
# allows. Without awk it is off the same way. No network, and no git call unless
# the command holds `git commit` or `git push`.
#
# What this guard does not catch. It is text matching on the command line, not a
# shell parser, so CI (the PR shape check) and scripts/pr-merge.sh are the layers
# that bind. Known misses:
#   - a command word split by a backslash in its middle (`g\h`); a backslash before the word (`\gh`) is read
#   - a command built from variables, functions, aliases or command substitution
#     (`$(gh pr merge 5)`, `$g push origin {{DEFAULT_BRANCH}}`); only the shape
#     `$g pr merge` is read
#   - a script, make target or tool that runs git or gh itself (`bash x.sh`,
#     `xargs`, `find -exec`, `ssh host ...`)
#   - a push configured away from its words (a git alias, `remote.<name>.push`,
#     `push.default`), and `git -c alias.x=push x`
#   - a merge from the GitHub site or any client other than gh
#   - a `gh api` merge that does not spell the method PUT as a word, or a graphql
#     call other than a literal `mergePullRequest`
#   - a commit made by a tool other than `git commit` (an editor, a GUI)
# What it does read: `;` `&&` `||` `|` and newline splits outside quotes, heredoc
# bodies are skipped, `bash -c` and `eval` payloads are checked, and the wrappers
# sudo, env, command, exec, nohup, time, nice, timeout, stdbuf and setsid are
# skipped, so `echo "gh pr merge"` and `rg 'git push'` pass.
set -o pipefail

default_branch="{{DEFAULT_BRANCH}}"
merge_cmd='bash scripts/pr-merge.sh --wait'

note() { printf 'agent-guard: %s\n' "$1" >&2; }

command -v jq >/dev/null 2>&1 || {
    note "jq is not installed, so the guard is off"
    exit 0
}
command -v awk >/dev/null 2>&1 || {
    note "awk is not installed, so the guard is off"
    exit 0
}

input="$(cat)" || exit 0
parsed="$(printf '%s' "$input" | jq -r '(.cwd // ""), (.tool_input.command // "")' 2>/dev/null)" || {
    note "could not read the hook input, allowing"
    exit 0
}
cmd="" cwd=""
case "$parsed" in
*"
"*)
    cwd="${parsed%%
*}"
    cmd="${parsed#*
}"
    ;;
esac
[ -n "$cmd" ] || exit 0

# Fast path: most commands never mention gh, git or a shell string.
case "$cmd" in
*gh* | *git* | *" -c"* | *eval* | *'$'*) ;;
*) exit 0 ;;
esac

eff_dir="${cwd:-$PWD}"
branch_override=""
depth=0

# A block ends the whole check. 42 is the private "blocked" signal that the outer
# wrapper turns into exit 2, so no other failure can ever read as a block.
block() { # block <rule> <fix>
    printf 'agent-guard: %s\nFix: %s\n' "$1" "$2" >&2
    exit 42
}

# One part per line; separators inside quotes become control characters, so a
# quoted `;` or `&&` does not split. Heredoc bodies are dropped.
split_parts() {
    awk '
    BEGIN { inq = ""; hd = "" }
    function flush() { if (seg ~ /[^ \t]/) print seg; seg = "" }
    {
        if (hd != "") {
            t = $0
            gsub(/^[ \t]+|[ \t]+$/, "", t)
            if (t == hd) hd = ""
            next
        }
        line = $0
        n = length(line)
        pending = ""
        for (i = 1; i <= n; i++) {
            c = substr(line, i, 1)
            if (inq != "") {
                if (c == inq) { inq = ""; seg = seg c }
                else if (inq == "\"" && c == "\\") { seg = seg c substr(line, i + 1, 1); i++ }
                else if (c == ";") seg = seg "\001"
                else if (c == "&") seg = seg "\002"
                else if (c == "|") seg = seg "\003"
                else seg = seg c
                continue
            }
            if (c == "\\") { seg = seg c substr(line, i + 1, 1); i++; continue }
            if (c == "\"" || c == "\047") { inq = c; seg = seg c; continue }
            if (c == "#" && (i == 1 || substr(line, i - 1, 1) ~ /[ \t]/)) break
            if (c == ";" || c == "&" || c == "|") { flush(); continue }
            if (c == "<" && substr(line, i, 2) == "<<" && substr(line, i, 3) != "<<<") {
                j = i + 2
                if (substr(line, j, 1) == "-") j++
                while (substr(line, j, 1) == " ") j++
                q = substr(line, j, 1)
                if (q == "\"" || q == "\047") j++
                w = ""
                while (j <= n && substr(line, j, 1) ~ /[A-Za-z0-9_]/) { w = w substr(line, j, 1); j++ }
                if (w != "") pending = w
                seg = seg "<<"
                i++
                continue
            }
            seg = seg c
        }
        if (inq != "") seg = seg "\004"
        else flush()
        if (pending != "") hd = pending
    }
    END { flush() }'
}

branch_of() { # branch_of <dir>
    if [ -n "$branch_override" ]; then
        printf '%s' "$branch_override"
        return
    fi
    git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null || true
}

resolve_dir() { # resolve_dir <path>: relative to the current effective dir
    local d="$1"
    case "$d" in
    "~"*) d="$HOME${d#\~}" ;;
    esac
    case "$d" in
    /*) printf '%s' "$d" ;;
    *) printf '%s/%s' "$eff_dir" "$d" ;;
    esac
}

is_branch() { # is_branch <dir> <name>: a local branch, or a remote one git would track
    git -C "$1" rev-parse --verify -q "refs/heads/$2" >/dev/null 2>&1 && return 0
    [ -n "$(git -C "$1" for-each-ref --format=x "refs/remotes/*/$2" 2>/dev/null)" ]
}

# block_merge <number> <branch word>: the fix names the PR when the command did.
block_merge() {
    local fix
    if [ -n "$1" ]; then
        fix="$merge_cmd $1"
    elif [ -n "$2" ]; then
        fix="$merge_cmd \"\$(gh pr view $2 --json number --jq .number)\""
    else
        fix="$merge_cmd \"\$(gh pr view --json number --jq .number)\""
    fi
    block "a bare gh pr merge skips the merge guard (checks, conflicts, one-way doors)." "$fix"
}

# check_pr_merge <words after merge>: find the PR number, else a branch word.
check_pr_merge() {
    local a skip=0 num="" word=""
    for a in "$@"; do
        if [ "$skip" -eq 1 ]; then
            skip=0
            continue
        fi
        case "$a" in
        -R | --repo | -b | --body | -F | --body-file | -t | --subject | -A | --author-email | --match-head-commit) skip=1 ;;
        -*) ;;
        *)
            [ -z "$num$word" ] || continue
            case "$a" in
            "") ;;
            *[!0-9]*)
                case "$a" in
                */pull/[0-9]*)
                    num="${a##*/pull/}"
                    num="${num%%[!0-9]*}"
                    ;;
                *[!A-Za-z0-9._/-]*) ;;
                *) word="$a" ;;
                esac
                ;;
            *) num="$a" ;;
            esac
            ;;
        esac
    done
    block_merge "$num" "$word"
}

# check_gh_api <words after api>: only a PUT to .../pulls/<n>/merge, or a literal
# mergePullRequest mutation, is read as a merge.
check_gh_api() {
    local a put=0 num="" merge=0
    for a in "$@"; do
        case "$a" in
        PUT | put | -XPUT | -Xput | --method=PUT | --method=put) put=1 ;;
        *mergePullRequest*) block_merge "" "" ;;
        */pulls/[0-9]*/merge*)
            merge=1
            num="${a#*/pulls/}"
            num="${num%%[!0-9]*}"
            ;;
        esac
    done
    if [ "$merge" -eq 1 ] && [ "$put" -eq 1 ]; then block_merge "$num" ""; fi
    return 0
}

# check_gh <words after gh>: group and verb are the first two words that are not flags.
check_gh() {
    local -a args=("$@")
    local j=0 m="${#args[@]}" group="" gi=0 verb="" vi=0
    while [ "$j" -lt "$m" ]; do
        case "${args[$j]}" in
        -R | --repo)
            j=$((j + 2))
            continue
            ;;
        -*) ;;
        *)
            if [ -z "$group" ]; then
                group="${args[$j]}"
                gi="$j"
            else
                verb="${args[$j]}"
                vi="$j"
                break
            fi
            ;;
        esac
        j=$((j + 1))
    done
    case "$group:$verb" in
    pr:merge) check_pr_merge "${args[@]:$((vi + 1))}" ;;
    api:*) check_gh_api "${args[@]:$((gi + 1))}" ;;
    esac
    return 0
}

check_git() { # check_git <words...>, the words after `git`
    local dir="$eff_dir" sub="" i=0
    local -a w=("$@")
    while [ "$i" -lt "${#w[@]}" ]; do
        case "${w[$i]}" in
        -C)
            dir="$(resolve_dir "${w[$((i + 1))]:-.}")"
            i=$((i + 2))
            ;;
        -c)
            i=$((i + 2))
            ;;
        -*) i=$((i + 1)) ;;
        *)
            sub="${w[$i]}"
            i=$((i + 1))
            break
            ;;
        esac
    done
    local -a rest=("${w[@]:$i}")

    case "$sub" in
    switch | checkout)
        # A branch change earlier in the same command decides the later parts.
        # `git checkout README.md` restores a file and switches nothing: a word
        # counts as a branch only after -b, -c or --create, or when it names a
        # branch that exists. A `--` marks the rest as paths.
        local target="" prev="" a created=0 pathmode=0 detach=0
        for a in "${rest[@]}"; do
            case "$prev" in
            -c | -b | -B | -C | --create | --force-create)
                if [ -z "$target" ]; then
                    target="$a"
                    created=1
                fi
                ;;
            esac
            case "$a" in
            --) pathmode=1 ;;
            -d | --detach) detach=1 ;;
            -*) ;;
            *) [ -n "$target" ] || target="$a" ;;
            esac
            prev="$a"
        done
        if [ "$pathmode" -eq 1 ]; then
            :
        elif [ "$detach" -eq 1 ]; then
            branch_override="(detached)"
        elif [ -n "$target" ] && { [ "$created" -eq 1 ] || is_branch "$dir" "$target"; }; then
            branch_override="$target"
        fi
        ;;
    commit)
        local a dry=0 b
        for a in "${rest[@]}"; do
            [ "$a" != "--dry-run" ] || dry=1
        done
        [ "$dry" -eq 0 ] || return 0
        b="$(branch_of "$dir")"
        if [ "$b" = "$default_branch" ]; then
            block "you are on $default_branch, and nothing commits to $default_branch directly (your changes come with you to a branch)." \
                "git switch -c <type>/<slug>"
        fi
        ;;
    push)
        local a skip=0 dry=0 tags=0 sweep=0 remote_seen=0 b r dst
        local -a refs=()
        for a in "${rest[@]}"; do
            if [ "$skip" -eq 1 ]; then
                skip=0
                continue
            fi
            case "$a" in
            -n | --dry-run) dry=1 ;;
            --tags) tags=1 ;;
            --all | --mirror) sweep=1 ;;
            -o | --push-option | --repo | --receive-pack | --exec) skip=1 ;;
            -*) ;;
            *)
                if [ "$remote_seen" -eq 0 ]; then
                    remote_seen=1
                else
                    refs+=("$a")
                fi
                ;;
            esac
        done
        [ "$dry" -eq 0 ] || return 0
        b="$(branch_of "$dir")"
        local msg="a push to $default_branch skips review, and nothing lands on $default_branch except through a PR."
        local fix="git switch -c <type>/<slug> && git push -u origin <type>/<slug> && gh pr create"
        if [ "$sweep" -eq 1 ]; then
            block "git push --all and --mirror push every branch, $default_branch included, and nothing lands on $default_branch except through a PR." \
                "git push -u origin <type>/<slug> && gh pr create"
        fi
        if [ "${#refs[@]}" -eq 0 ]; then
            if [ "$tags" -eq 0 ] && [ "$b" = "$default_branch" ]; then block "$msg" "$fix"; fi
            return 0
        fi
        for r in "${refs[@]}"; do
            r="${r#+}"
            case "$r" in
            *:*) dst="${r#*:}" ;;
            *) dst="$r" ;;
            esac
            dst="${dst#refs/heads/}"
            if [ "$dst" = "$default_branch" ]; then block "$msg" "$fix"; fi
            if [ "$dst" = "HEAD" ] && [ "$b" = "$default_branch" ]; then block "$msg" "$fix"; fi
        done
        ;;
    esac
    return 0
}

check_segment() { # check_segment <one part>
    local seg="$1" word i=0
    local -a w=()
    # shellcheck disable=SC2162
    read -a w <<<"$seg" || true
    local n="${#w[@]}"
    local -a c=()
    for ((i = 0; i < n; i++)); do
        word="${w[$i]//\"/}"
        word="${word//\'/}"
        c+=("${word//\\/}") # a backslash before a word (\gh) is the same word to the shell
    done

    # Skip shell keywords, VAR=value words and command wrappers (with their own
    # flags and the timeout duration) to reach the real command word.
    local wrapped=0 prevw=""
    i=0
    while [ "$i" -lt "$n" ]; do
        word="${c[$i]#(}"
        case "$word" in
        "" | if | then | else | do | while | until | '!' | '{') i=$((i + 1)) ;;
        sudo | env | command | exec | nohup | time | nice | timeout | stdbuf | setsid)
            wrapped=1
            prevw="$word"
            i=$((i + 1))
            ;;
        [A-Za-z_]*=*) i=$((i + 1)) ;;
        -n | -u | -s | -k | -g | -C | -U | -S)
            [ "$wrapped" -eq 1 ] || break
            i=$((i + 2))
            ;;
        -*)
            [ "$wrapped" -eq 1 ] || break
            i=$((i + 1))
            ;;
        [0-9]*)
            [ "$prevw" = "timeout" ] || break
            prevw=""
            i=$((i + 1))
            ;;
        *) break ;;
        esac
    done
    [ "$i" -lt "$n" ] || return 0
    local first="${c[$i]#(}"
    case "$first" in
    '$'*) ;;
    *) first="${first##*/}" ;;
    esac
    local -a args=("${c[@]:$((i + 1))}")

    case "$first" in
    cd | pushd)
        case "${args[0]:-}" in
        "" | - | *'$'*) ;;
        *) eff_dir="$(resolve_dir "${args[0]}")" ;;
        esac
        ;;
    gh | '$'*)
        check_gh "${args[@]}"
        ;;
    git)
        check_git "${args[@]}"
        ;;
    bash | sh | zsh | dash | ksh | eval)
        [ "$depth" -lt 3 ] || return 0
        local k=0 m="${#args[@]}" found=0
        if [ "$first" = "eval" ]; then
            found=1
        else
            while [ "$k" -lt "$m" ]; do
                case "${args[$k]}" in
                -c | -[a-z]*c)
                    found=1
                    k=$((k + 1))
                    break
                    ;;
                esac
                k=$((k + 1))
            done
        fi
        if [ "$found" -eq 1 ]; then
            local payload="${args[*]:$k}"
            payload="$(printf '%s' "$payload" | tr '\001\002\003\004' ';&|\n')"
            depth=$((depth + 1))
            check_command "$payload"
            depth=$((depth - 1))
        fi
        ;;
    esac
    return 0
}

check_command() { # check_command <command string>
    local line
    while IFS= read -r line; do
        check_segment "$line"
    done <<EOF
$(printf '%s\n' "$1" | split_parts 2>/dev/null)
EOF
    return 0
}

( check_command "$cmd" )
rc=$?
[ "$rc" -ne 42 ] || exit 2
exit 0
