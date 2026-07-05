#!/usr/bin/env bash
# parse-board.sh -- the ONE structured board parser (SPEC-146, runner-fastpath sub-goal 04).
#
# `lib/backlog.sh`'s own `_rows()` is a private, minimal row-extractor (id/title/status only).
# This is the reusable, PUBLIC surface other tools parse a BACKLOG.md through: `lib/board.sh`'s
# `queue` subcommand uses it today; the runner-fastpath design (SG-07/08, board-bridge mirror +
# writeback) is EXPECTED to reuse it rather than re-parsing the markdown a third time.
#
# Two functions, two CLI verbs:
#
#   pb_rows <file>
#     -> id<TAB>status<TAB>full-row-line   (one line per Active-queue row; section headers and
#        non-matching lines are skipped, same id/status extraction as backlog.sh's _rows())
#
#   pb_queue_rows <file> <repo-name> <repo-root>
#     -> id<TAB>repo-root<TAB>resolved-pointer-path   (one line per VALID queue candidate)
#
#     A row is a queue candidate only if its status leading-keyword is exactly "queued" AND its
#     row text carries a marker of the shape:
#
#       #queue{repo=<name>,pointer=<relative/path/to/file.md>}
#
#     (anywhere in the row's text -- same inline-tag convention `board.sh priority`'s #u-hi/#f-hi
#     tags already use). Both `repo=` and `pointer=` are REQUIRED; unrecognized keys are ignored.
#
#     ALLOW-LIST (load-bearing security, rung-4 threat: a free-text Notes cell feeds an
#     unattended runner downstream):
#       1. repo/pointer charset: repo matches ^[A-Za-z0-9_-]+$, pointer matches
#          ^[A-Za-z0-9_./-]+$ and is RELATIVE (no leading `/`, no `..` path component). Anything
#          else is malformed -> skipped. This alone defeats shell-metachar injection (`;`, `$`,
#          backticks, spaces, newlines are all outside the allowed charset) -- the token is never
#          accepted, so it can never reach an exec boundary.
#       2. repo self-consistency: the token's `repo=` value MUST equal the `<repo-name>` this
#          function was called with (the name of the repo whose BACKLOG.md is being parsed).
#          A row in repo X's own board claiming `repo=Y` is a cross-repo spoofing attempt and is
#          refused, not silently "corrected" to X.
#       3. pointer containment: `<repo-root>/<pointer>` is lexically canonicalized (`..`/`.`
#          resolved WITHOUT requiring the path to exist) and must resolve to a path starting with
#          `<repo-root>/_meta/megagoals/` or `<repo-root>/.claude/goals/` (trailing slash in the
#          prefix check, so `_meta/megagoals-evil` cannot match `_meta/megagoals`).
#       4. existence: the resolved pointer file must actually exist (a dangling allow-listed
#          pointer is useless to a downstream runner and is treated the same as malformed).
#     Any failure is a SKIP, never a hard error: this function's job is "emit only what is safe",
#     the caller (lib/board.sh queue) counts skips and always exits 0 (honest-empty is a result,
#     not a failure).
#
# Skip reasons are printed to STDERR as `parse-board: skip <id> (<repo-name>): <reason>`, never
# mixed into the TAB-separated stdout stream (stdout stays machine-parseable for a downstream
# argv-exec consumer; never eval'd, never passed through a shell).
#
# BACKLOG_ID_RE overrides the id pattern (default matches lib/backlog.sh's own default).

set -euo pipefail

BACKLOG_ID_RE="${BACKLOG_ID_RE:-[A-Z]+-[0-9]+}"

# ---------------------------------------------------------------------------
# pb_rows <file> -- id\tstatus\tfull-row-line, one per Active-queue row.
# ---------------------------------------------------------------------------
pb_rows() {
  local file="$1"
  awk -F'|' -v idre="$BACKLOG_ID_RE" '
    $0 ~ ("^\\| *" idre " *\\|") {
      id=$2; gsub(/^[ \t]+|[ \t]+$/, "", id)
      status=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", status)
      split(status, a, /[ \[(]/); lead=a[1]
      printf "%s\t%s\t%s\n", id, lead, $0
    }' "$file"
}

# _canon_path <path> -- lexical `..`/`.` resolution; does NOT require the path to exist and does
# NOT follow symlinks (a threat model where the repos in boards.txt are trusted, Han-owned repos;
# the risk is a hand-authored `../` in a Notes cell, not an attacker-planted symlink). Always
# printed as an absolute path (relative inputs are resolved against $PWD, but every caller here
# passes an already-absolute "<repo-root>/<pointer>" input).
_canon_path() {
  local path="$1" part
  case "$path" in /*) ;; *) path="$PWD/$path" ;; esac
  local stack=()
  local IFS=/
  # shellcheck disable=SC2086 # intentional word-split on IFS=/ above
  for part in $path; do
    case "$part" in
      ''|'.') continue ;;
      # Positive-index unset (NOT `stack[-1]`): bash 3.2 -- the macOS system /bin/bash, which
      # some CI runners resolve `bash` to -- has no negative array indices (a 4.3+ feature).
      '..') [ ${#stack[@]} -gt 0 ] && unset "stack[$((${#stack[@]}-1))]" ;;
      *) stack+=("$part") ;;
    esac
  done
  ( IFS=/; printf '/%s\n' "${stack[*]:-}" )
}

# _pb_skip <id> <repo-name> <reason> -- uniform skip-log line to stderr.
_pb_skip() {
  echo "parse-board: skip $1 ($2): $3" >&2
}

# ---------------------------------------------------------------------------
# pb_queue_rows <file> <repo-name> <repo-root> -- id\trepo-root\tresolved-pointer, one per
# ALLOW-LISTED queue candidate. See the header comment above for the full allow-list contract.
# ---------------------------------------------------------------------------
pb_queue_rows() {
  local file="$1" repo_name="$2" repo_root="$3"
  # Canonicalize repo_root itself (not just the joined pointer path): a caller-supplied root
  # containing a double slash or a trailing `.`/`..` (e.g. macOS's $TMPDIR, which commonly ends
  # in a trailing slash, so "$TMPDIR/x" becomes ".../T//x") would otherwise canonicalize the
  # JOINED path but compare it against a non-canonical prefix, making a legitimately in-bounds
  # pointer fail the containment check on a STRING mismatch alone.
  repo_root="$(_canon_path "$repo_root")"
  local id status line tag inner kv key val repo pointer resolved

  while IFS=$'\t' read -r id status line; do
    [ -n "$id" ] || continue
    [ "$status" = "queued" ] || continue   # non-queued rows are silently out of scope

    tag="$(printf '%s' "$line" | grep -oE '#queue\{[^}]*\}' | head -n1 || true)"
    [ -n "$tag" ] || continue   # a queued row with no #queue{} marker is just a normal row

    inner="${tag#\#queue\{}"; inner="${inner%\}}"
    repo=""; pointer=""
    local kvs=() had_repo_key=0 had_pointer_key=0
    IFS=',' read -ra kvs <<< "$inner"
    for kv in "${kvs[@]}"; do
      key="${kv%%=*}"; val="${kv#*=}"
      case "$key" in
        repo)    repo="$val";    had_repo_key=1 ;;
        pointer) pointer="$val"; had_pointer_key=1 ;;
        *) ;;  # unrecognized keys ignored (forward-compatible with a future 3rd field)
      esac
    done

    if [ "$had_repo_key" -eq 0 ] || [ "$had_pointer_key" -eq 0 ] || [ -z "$repo" ] || [ -z "$pointer" ]; then
      _pb_skip "$id" "$repo_name" "malformed #queue{} token (missing repo= or pointer=)"
      continue
    fi

    # --- charset gate (defeats shell-metachar / newline / command-substitution injection) ---
    if ! [[ "$repo" =~ ^[A-Za-z0-9_-]+$ ]]; then
      _pb_skip "$id" "$repo_name" "token repo field has disallowed characters"
      continue
    fi
    if ! [[ "$pointer" =~ ^[A-Za-z0-9_./-]+$ ]]; then
      _pb_skip "$id" "$repo_name" "token pointer field has disallowed characters"
      continue
    fi
    case "$pointer" in
      /*) _pb_skip "$id" "$repo_name" "pointer must be relative (got absolute: $pointer)"; continue ;;
    esac
    # Wrapping in slashes means ANY ".." component (leading, trailing, or interior) always
    # produces a "/../" substring somewhere -- one glob alternative covers every position.
    case "/$pointer/" in
      */../*) _pb_skip "$id" "$repo_name" "pointer contains a '..' path component ($pointer)"; continue ;;
    esac

    # --- repo self-consistency (cross-repo spoofing defense) ---
    if [ "$repo" != "$repo_name" ]; then
      _pb_skip "$id" "$repo_name" "repo mismatch: token claims '$repo' but this row is in '$repo_name' board (not in boards.txt for this file, or spoofed)"
      continue
    fi

    # --- pointer containment (path-traversal hardening) ---
    resolved="$(_canon_path "$repo_root/$pointer")"
    case "$resolved" in
      "$repo_root"/_meta/megagoals/*|"$repo_root"/.claude/goals/*) : ;;
      *) _pb_skip "$id" "$repo_name" "pointer resolves outside allow-listed dirs ($resolved)"; continue ;;
    esac

    # --- existence ---
    if [ ! -f "$resolved" ]; then
      _pb_skip "$id" "$repo_name" "pointer file does not exist ($resolved)"
      continue
    fi

    printf '%s\t%s\t%s\n' "$id" "$repo_root" "$resolved"
  done < <(pb_rows "$file")
}

usage() { sed -n '2,40p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    rows)        pb_rows "$@" ;;
    queue-rows)  pb_queue_rows "$@" ;;
    ""|-h|--help|help) usage ;;
    *) echo "parse-board.sh: unknown subcommand '$sub'" >&2; usage >&2; return 64 ;;
  esac
}

# Allow this file to be sourced (functions only, no dispatch) OR run directly as a CLI.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
