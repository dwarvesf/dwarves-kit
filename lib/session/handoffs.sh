#!/usr/bin/env bash
# handoffs.sh -- list open handoff files so kit:start surfaces them at session
# entry instead of them piling up unread, and archive a finished one. A handoff
# (written by the `handoff` skill) is a one-off note, not a lifecycle-managed
# draft like .claude/goals/ (see lib/goal/goal-drafts.sh): the scan is one level
# deep. A file sitting directly in a scan root is open; a file a repo moves into
# ANY subdirectory (done/, _archive/, archive/, a nested .claude/, or any other
# name a repo invents) counts as consumed. No name list is maintained anywhere;
# depth alone decides. `archive` is the one writer: it moves a file to archive/.
#
# `list` is read-only; `archive` writes (one git mv or mv, never a delete).
# Pure bash + find/awk/sed, no python (same shape as
# lib/session/parse-transcript.sh's sibling test, lib/session/tests/).
#
# Usage:
#   handoffs.sh archive [--repo DIR] <file>
#     --repo DIR   repo whose checkout holds the file (default as for list). For
#                  a tracked file pass the worktree of the session's branch.
#     <file>       a top-level *.md file of <repo>/_meta/handoffs/ or
#                  <repo>/.claude/handoffs/, absolute or repo-relative. Moves it
#                  into <dir>/archive/ (created): `git mv` when tracked, `mv -n`
#                  when untracked. One outcome line, `archived (git mv|mv): ...`
#                  or `REFUSED: <reason>` (exit 1). Refuses a nested file, a
#                  symlink, an existing target, and a tracked file while the
#                  checkout is on the default branch (the move belongs on a
#                  branch). Never deletes anything.
#
#   handoffs.sh list [--repo DIR] [--under [ROOT]]... [--days N] [--limit N]
#     --repo DIR   repo to scan (default: git rev-parse --show-toplevel of
#                  cwd, else cwd itself)
#     --under ROOT scan every immediate child of ROOT that holds a .git file or
#                  directory, sorted (same rule as `wrap scan --under`).
#                  Repeatable; `--under=ROOT` also works. A bare `--under` (no
#                  ROOT, or a flag next) expands the wrap.roots knob, root-only
#                  config. Output switches to grouped form: per repo with at
#                  least one open handoff, a `## <repo path>` header then that
#                  repo's lines (no per-repo count), repos with none print
#                  nothing, and the last line is
#                  "<n> open handoffs in <m> repos" (n uncapped). A root with no
#                  git repos prints a note on stderr. Without --under the
#                  output is exactly as before.
#     --days N     only include handoffs at least N days old (staleness
#                  filter; default: no filter, show every open handoff);
#                  applies per repo under --under
#     --limit N    max handoff lines to print before collapsing the rest to
#                  "+N more" (default: 5; 0 means unlimited); per repo under
#                  --under
#
#   Scans <repo>/_meta/handoffs/ and <repo>/.claude/handoffs/ for *.md files
#   sitting directly in either directory, one level deep, no recursion: a
#   file moved into any subdirectory, whatever it is named, is treated as
#   consumed. One line per
#   file, oldest first:
#     <age>d  <repo-relative path>  next: <excerpt>  <liveness>
#   <excerpt> is the first non-empty line under a heading matching
#   /^## (Next|Next step|Open)/, truncated to 80 chars, or
#   "(no Next section)" when no such heading exists. Past --limit lines, the
#   rest collapse to one "+N more" line. Last line is "<n> open handoffs"
#   (the true total, uncapped), or "no handoffs" when the scan found none.
#
#   <liveness> checks every board ID (`[A-Z]+-[0-9]+`) the file cites
#   against the repo's board AS IT STANDS ON ORIGIN (`git fetch origin`,
#   then `_meta/BACKLOG.md` + `_meta/BACKLOG-archive.md` off
#   origin/<default-branch>), falling back to the working tree with a
#   "(local)" suffix when there is no origin remote:
#     LIVE (n open: ID-a, ID-b)   -- at least one cited row is still open
#     DEAD (all n cited rows closed, move it to archive/)  -- every cited
#       row shipped/dropped/done/resolved
#     UNCITED (no row IDs; read it)  -- the file names no board row
#   A row ID this repo's board cannot resolve counts as open (unproven, not
#   confirmed closed). The board owns the work; the handoff owns only the
#   context (see AGENTS.md's handoff rule). A DEAD handoff is moved to
#   archive/ (`handoffs.sh archive`) by the session that finds it, never
#   deleted.
set -euo pipefail
shopt -s nullglob

usage() { sed -n '2,/^[^#]/p' "${BASH_SOURCE[0]}" | sed '$d; s/^# \{0,1\}//'; }

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || pwd
}

# First non-empty line under a heading matching /^## (Next|Next step|Open)/,
# truncated to 80 chars. Empty output means no such heading was found.
next_excerpt() { # <file>
  awk '
    /^## (Next|Next step|Open)/ { infm=1; next }
    infm && /^#/ { exit }
    infm && NF > 0 { print; exit }
  ' "$1" | cut -c1-80
}

# --- board liveness ----------------------------------------------------

# Best-effort default branch of origin: refs/remotes/origin/HEAD symref
# (set by a normal clone), else the first of master/main that exists.
_origin_default_branch() { # <repo>
  local repo="$1" ref cand
  ref="$(git -C "$repo" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  if [ -n "$ref" ]; then printf '%s\n' "${ref#origin/}"; return 0; fi
  for cand in master main; do
    if git -C "$repo" show-ref --verify --quiet "refs/remotes/origin/$cand"; then
      printf '%s\n' "$cand"; return 0
    fi
  done
  return 1
}

# Loads the board content this repo's liveness checks should read against,
# into the globals BOARD_CONTENT (BACKLOG.md + BACKLOG-archive.md,
# concatenated) and BOARD_SOURCE ("origin/<branch>" or "local"). Origin
# first, working tree only when there is no origin remote or no resolvable
# default branch.
_load_board() { # <repo>
  local repo="$1" branch
  BOARD_CONTENT="" BOARD_SOURCE="local"
  if git -C "$repo" remote get-url origin >/dev/null 2>&1; then
    git -C "$repo" fetch -q origin >/dev/null 2>&1 || true
    branch="$(_origin_default_branch "$repo" || true)"
    if [ -n "$branch" ]; then
      BOARD_CONTENT="$(git -C "$repo" show "origin/$branch:_meta/BACKLOG.md" 2>/dev/null || true)"
      BOARD_CONTENT="$BOARD_CONTENT
$(git -C "$repo" show "origin/$branch:_meta/BACKLOG-archive.md" 2>/dev/null || true)"
      BOARD_SOURCE="origin/$branch"
      return 0
    fi
  fi
  BOARD_CONTENT="$(cat "$repo/_meta/BACKLOG.md" 2>/dev/null || true)"
  BOARD_CONTENT="$BOARD_CONTENT
$(cat "$repo/_meta/BACKLOG-archive.md" 2>/dev/null || true)"
}

# Leading status keyword of one board row (lowercased), or empty when the
# id has no row in BOARD_CONTENT.
_row_status() { # <id>
  printf '%s\n' "$BOARD_CONTENT" | awk -F'|' -v id="$1" '
    $0 ~ ("^\\| *" id " *\\|") {
      cell=$(NF-1); gsub(/^[ \t]+|[ \t]+$/, "", cell)
      split(cell, a, /[ \[(]/); print tolower(a[1]); exit
    }'
}

_status_is_closed() { # <status>
  case "$1" in
    shipped|dropped|done|resolved) return 0 ;;
    *) return 1 ;;
  esac
}

# One-line liveness verdict for a handoff file, reading the already-loaded
# BOARD_CONTENT/BOARD_SOURCE globals (see _load_board).
handoff_liveness() { # <file>
  local f="$1" ids id status n=0
  local open=()
  ids="$(grep -oE '[A-Z]+-[0-9]+' "$f" 2>/dev/null | sort -u || true)"
  [ -n "$ids" ] || { echo "UNCITED (no row IDs; read it)"; return 0; }
  for id in $ids; do
    n=$((n + 1))
    status="$(_row_status "$id")"
    if [ -n "$status" ] && _status_is_closed "$status"; then
      continue
    fi
    open+=("$id")
  done
  local suffix=""
  [ "$BOARD_SOURCE" = "local" ] && suffix=" (local)"
  if [ "${#open[@]}" -eq 0 ]; then
    echo "DEAD (all $n cited rows closed, move it to archive/)$suffix"
  else
    local joined; joined="$(IFS=,; echo "${open[*]}")"
    joined="$(printf '%s' "$joined" | sed 's/,/, /g')"
    echo "LIVE (${#open[@]} open: $joined)$suffix"
  fi
}

# _list_one <repo> <days> <limit> -- scan one repo (already an existing dir). Sets the
# globals LIST_N (open handoffs after --days, uncapped) and LIST_OUT (the capped,
# oldest-first lines, "+N more" included, no count line). Both empty/0 when none.
_list_one() {
  local repo="$1" days="$2" limit="$3"
  LIST_N=0 LIST_OUT=""
  local files=()
  local d f
  for d in "$repo/_meta/handoffs" "$repo/.claude/handoffs"; do
    [ -d "$d" ] || continue
    while IFS= read -r f; do
      files+=("$f")
    done < <(find "$d" -maxdepth 1 -type f -name '*.md' 2>/dev/null)
  done
  [ "${#files[@]}" -gt 0 ] || return 0

  _load_board "$repo"

  local now; now="$(date +%s)"
  local rows=()
  for f in "${files[@]}"; do
    local mtime age rel excerpt liveness
    mtime="$(stat -f '%m' "$f" 2>/dev/null || stat -c '%Y' "$f" 2>/dev/null)"
    age=$(( (now - mtime) / 86400 ))
    [ -n "$days" ] && [ "$age" -lt "$days" ] && continue
    rel="${f#"$repo"/}"
    excerpt="$(next_excerpt "$f")"
    [ -n "$excerpt" ] || excerpt="(no Next section)"
    liveness="$(handoff_liveness "$f")"
    rows+=("$(printf '%09d\t%sd  %s  next: %s  %s' "$age" "$age" "$rel" "$excerpt" "$liveness")")
  done
  [ "${#rows[@]}" -gt 0 ] || return 0

  # Sort oldest first (largest age first) by the zero-padded sort key, then
  # strip the key before printing.
  local sorted; sorted="$(printf '%s\n' "${rows[@]}" | sort -rn -t"$(printf '\t')" -k1,1 | cut -f2-)"
  LIST_N="${#rows[@]}"
  if [ "$limit" -gt 0 ] && [ "$LIST_N" -gt "$limit" ]; then
    LIST_OUT="$(printf '%s\n' "$sorted" | head -n "$limit")
+$((LIST_N - limit)) more"
  else
    LIST_OUT="$sorted"
  fi
}

# _under_add <root> -- append every immediate child of <root> holding a .git file or
# directory, sorted, to the CALLER's `under_repos` array. Same rule as `_add_under` in
# lib/wrap/wrap-scan.sh (not sourced: that file needs wrap.sh's whole environment).
_under_add() {
  local found r
  found="$(for r in "${1%/}"/*/; do [ -e "${r}.git" ] && printf '%s\n' "${r%/}"; done | LC_ALL=C sort)"
  if [ -z "$found" ]; then echo "handoffs list: ${1}: --under found no git repos" >&2; return 0; fi
  while IFS= read -r r; do under_repos+=("$r"); done <<< "$found"
}

# _under_expand_bare -- a bare `--under` expands every root of the wrap.roots knob
# (tilde-expanded, listed order) onto the CALLER's `unders` array. Root-only config read,
# as in wrap. An empty knob is an error, so a bare --under never silently means "nothing".
_under_expand_bare() {
  local kit roots r
  kit="$(cd "$(dirname "${BASH_SOURCE[0]}")/../config" 2>/dev/null && pwd)/kit-config.sh"
  [ -r "$kit" ] || { echo "handoffs list: $kit missing or unreadable" >&2; return 1; }
  # shellcheck source=lib/config/kit-config.sh
  source "$kit"
  roots="$(kit_config_get_root wrap.roots "")"
  if [ -z "$roots" ]; then
    echo "handoffs list: --under given no directory and wrap.roots is empty" >&2
    return 64
  fi
  for r in $roots; do
    case "$r" in
      "~") r="$HOME" ;;
      "~/"*) r="$HOME/${r#\~/}" ;;
    esac
    unders+=("$r")
  done
}

cmd_list() {
  local repo="" days="" limit=5 want_under=0
  local unders=() under_repos=()
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] || { echo "handoffs list: --repo needs a value" >&2; return 64; }; repo="$2"; shift 2 ;;
      --days) [ $# -ge 2 ] || { echo "handoffs list: --days needs a value" >&2; return 64; }; days="$2"; shift 2 ;;
      --limit) [ $# -ge 2 ] || { echo "handoffs list: --limit needs a value" >&2; return 64; }; limit="$2"; shift 2 ;;
      --under=*) unders+=("${1#--under=}"); shift ;;
      --under)
        # A value that is not a flag is the root; otherwise this is the bare form.
        if [ $# -ge 2 ] && [ "${2#-}" = "$2" ]; then unders+=("$2"); shift 2
        else want_under=1; shift; fi ;;
      *) echo "handoffs list: unknown arg '$1'" >&2; return 64 ;;
    esac
  done
  case "$limit" in
    ''|*[!0-9]*) echo "handoffs list: --limit must be a non-negative integer (got '$limit')" >&2; return 64 ;;
  esac

  if [ "$want_under" = 1 ] || [ "${#unders[@]}" -gt 0 ]; then
    local rc=0 u r total=0 nrepos=0
    [ "$want_under" = 0 ] || _under_expand_bare || { rc=$?; return "$rc"; }
    [ -z "$repo" ] || under_repos+=("$repo")
    for u in "${unders[@]}"; do _under_add "$u"; done
    for r in "${under_repos[@]+"${under_repos[@]}"}"; do
      [ -d "$r" ] || { echo "handoffs list: repo not found: $r" >&2; continue; }
      _list_one "$(cd "$r" && pwd)" "$days" "$limit"
      [ "$LIST_N" -gt 0 ] || continue
      printf '## %s\n%s\n' "$r" "$LIST_OUT"
      total=$((total + LIST_N)); nrepos=$((nrepos + 1))
    done
    echo "$total open handoffs in $nrepos repos"
    return 0
  fi

  [ -n "$repo" ] || repo="$(repo_root)"
  repo="$(cd "$repo" 2>/dev/null && pwd || true)"
  [ -n "$repo" ] || { echo "handoffs list: repo not found" >&2; return 1; }

  _list_one "$repo" "$days" "$limit"
  if [ "$LIST_N" -eq 0 ]; then
    echo "no handoffs"
    return 0
  fi
  printf '%s\n' "$LIST_OUT"
  echo "$LIST_N open handoffs"
}

# Archive one finished handoff. The one writer in this file: a git mv (tracked)
# or mv -n (untracked) into <dir>/archive/, never a delete. Prints one line.
_archive_refuse() { echo "REFUSED: $*" >&2; return 1; }

cmd_archive() {
  local repo="" file=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo) [ $# -ge 2 ] || { echo "handoffs archive: --repo needs a value" >&2; return 64; }; repo="$2"; shift 2 ;;
      -*) echo "handoffs archive: unknown arg '$1'" >&2; return 64 ;;
      *) [ -z "$file" ] || { echo "handoffs archive: one file only" >&2; return 64; }; file="$1"; shift ;;
    esac
  done
  [ -n "$file" ] || { echo "handoffs archive: needs a <file>" >&2; return 64; }
  [ -n "$repo" ] || repo="$(repo_root)"
  repo="$(cd "$repo" 2>/dev/null && pwd -P || true)"
  [ -n "$repo" ] || { echo "handoffs archive: repo not found" >&2; return 1; }

  case "$file" in /*) ;; *) file="$repo/$file" ;; esac
  [ -L "$file" ] && { _archive_refuse "$file is a symlink"; return 1; }
  [ -f "$file" ] || { _archive_refuse "$file is not a file"; return 1; }
  local dir base
  dir="$(cd "$(dirname "$file")" && pwd -P)"
  base="$(basename "$file")"
  case "$base" in *.md) ;; *) _archive_refuse "$base is not a .md file"; return 1 ;; esac
  case "$dir" in
    "$repo/_meta/handoffs"|"$repo/.claude/handoffs") ;;
    *) _archive_refuse "$base is not a top-level file of _meta/handoffs/ or .claude/handoffs/ in $repo"; return 1 ;;
  esac

  local src="$dir/$base" dest="$dir/archive/$base" rel_src rel_dest
  rel_src="${src#"$repo"/}"; rel_dest="${dest#"$repo"/}"
  [ ! -e "$dest" ] && [ ! -L "$dest" ] || { _archive_refuse "$rel_dest already exists"; return 1; }

  if git -C "$repo" ls-files --error-unmatch -- "$rel_src" >/dev/null 2>&1; then
    local cur def
    cur="$(git -C "$repo" symbolic-ref --short -q HEAD || true)"
    def="$(_origin_default_branch "$repo" || true)"
    if [ -z "$cur" ] || [ "$cur" = "$def" ] || { [ -z "$def" ] && { [ "$cur" = master ] || [ "$cur" = main ]; }; }; then
      _archive_refuse "$rel_src is tracked and $repo is on '${cur:-detached HEAD}'; move it on a branch in a worktree"
      return 1
    fi
    mkdir -p "$dir/archive"
    git -C "$repo" mv -- "$rel_src" "$rel_dest" >/dev/null || { _archive_refuse "git mv failed for $rel_src"; return 1; }
    echo "archived (git mv): $rel_src -> $rel_dest"
  else
    mkdir -p "$dir/archive"
    command mv -n "$src" "$dest" || { _archive_refuse "mv failed for $rel_src"; return 1; }
    [ ! -e "$src" ] || { _archive_refuse "mv left $rel_src in place"; return 1; }
    echo "archived (mv): $rel_src -> $rel_dest"
  fi
}

main() {
  local sub="${1:-}"; [ $# -gt 0 ] && shift || true
  case "$sub" in
    list) cmd_list "$@" ;;
    archive) cmd_archive "$@" ;;
    -h|--help|help|"") usage ;;
    *) echo "handoffs: unknown subcommand '$sub' (try: handoffs.sh --help)" >&2; return 64 ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  main "$@"
fi
