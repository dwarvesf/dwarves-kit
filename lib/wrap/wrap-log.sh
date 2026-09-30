# wrap-log.sh -- the log, knowledge-root, and stage verbs with their helpers; sourced by lib/wrap/wrap.sh.

# --------------------------------------------------------------------------- log

# _realpath_f <path> -- absolute path with every symlink on it resolved. The directory must
# exist; the leaf need not.
_realpath_f() {
  local p="$1" dir base tgt n=0
  dir="$(cd "$(dirname "$p")" 2>/dev/null && pwd -P)" || return 1
  base="$(basename "$p")"
  while [ -L "$dir/$base" ] && [ "$n" -lt 16 ]; do
    tgt="$(readlink "$dir/$base")"
    case "$tgt" in /*) ;; *) tgt="${dir}/${tgt}" ;; esac
    dir="$(cd "$(dirname "$tgt")" 2>/dev/null && pwd -P)" || return 1
    base="$(basename "$tgt")"
    n=$(( n + 1 ))
  done
  printf '%s/%s\n' "${dir%/}" "$base"
}

# _home_fence <path> [<label>] -- 0 when <path> is the physical $HOME or sits under it.
# The fence resolves its own argument: a caller that forgets to resolve first would otherwise
# fence a string whose parent directory is a symlink pointing anywhere on disk. $HOME itself
# is accepted so this fence agrees with `_under_home`, the parity `config seams` reports on.
# Prints the reason and returns 1 otherwise.
_home_fence() {
  local p="$1" label="${2:-wrap}" home_real real
  home_real="$(cd "$HOME" 2>/dev/null && pwd -P)" \
    || { echo "${label}: cannot resolve HOME" >&2; return 1; }
  real="$(_realpath_f "$p")" || { echo "${label}: cannot resolve '${p}'" >&2; return 1; }
  case "$real" in
    "$home_real"|"$home_real"/*) return 0 ;;
    *) echo "${label}: '${real}' is outside HOME (${home_real})" >&2; return 1 ;;
  esac
}

# _refuse_symlink <path> [<label>] -- 1 when <path> is a symlink. A symlink at a write target
# redirects the append to whatever it points at, so every write path refuses one.
_refuse_symlink() {
  local p="$1" label="${2:-wrap}"
  [ -L "$p" ] || return 0
  echo "${label}: '${p}' is a symlink" >&2
  return 1
}

# _worktree_copy <file>: the configured log names one fixed file, usually inside a repo's
# main checkout. A session that works in a git worktree of that same repo cannot commit a
# line written to the main checkout (its branch is not the session's), so when the current
# directory is a worktree sharing the file's repo, the same repo-relative path inside the
# current worktree is the target. Prints the path to use; the input when nothing applies.
_worktree_copy() {
  local file="$1" fdir fcommon ftop cur_common cur_top rel
  fdir="$(dirname "$file")"
  fcommon="$(git -C "$fdir" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { printf '%s' "$file"; return 0; }
  ftop="$(git -C "$fdir" rev-parse --show-toplevel 2>/dev/null)" || { printf '%s' "$file"; return 0; }
  cur_common="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || { printf '%s' "$file"; return 0; }
  cur_top="$(git rev-parse --show-toplevel 2>/dev/null)" || { printf '%s' "$file"; return 0; }
  [ "$fcommon" = "$cur_common" ] || { printf '%s' "$file"; return 0; }
  [ "$ftop" != "$cur_top" ] || { printf '%s' "$file"; return 0; }
  rel="${file#"$ftop"/}"
  # `[ -f ]` follows symlinks, so this gate accepts a symlink whose target is a regular file
  # anywhere on disk. The returned path is a NEW path no earlier check saw: every caller must
  # re-run its symlink refusal and its fence on the value this prints.
  [ -f "$cur_top/$rel" ] || { printf '%s' "$file"; return 0; }
  printf '%s' "$cur_top/$rel"
}

# _log_anchor_head_lines <file>: prints how many lines of <file> stay ABOVE the new entry.
# The anchor is the first line that is exactly `---` (the header/entries separator), plus
# any blank lines immediately following it, so the new entry lands as the newest ENTRY, not
# above the file's title. If line 1 is itself `---` (a YAML frontmatter opening delimiter),
# the frontmatter's own closing `---` is the SECOND such line and becomes the anchor instead,
# so the entry never lands inside frontmatter. Prints 0 when no anchor line exists at all
# (or line 1 is `---` with no closing delimiter): the caller falls back to the old prepend-at-
# line-0 behavior rather than failing, since a file with no recognizable header has no wrong
# place to land above, and every pre-anchor-rule caller already depends on that prepend shape.
_log_anchor_head_lines() {
  awk '
    NR==1 { want = ($0=="---") ? 2 : 1 }
    state==0 {
      if ($0=="---") { c++; if (c==want) { state=1; head=NR } }
      next
    }
    state==1 {
      if ($0=="") { head=NR; next }
      state=2
    }
    END { print head+0 }
  ' "$1"
}

cmd_log() {
  local date_str text="" arg have_text=0
  date_str="$(date +%F)"
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --date) [ $# -ge 2 ] || { echo "usage: wrap.sh log [--date YYYY-MM-DD] \"<slug>: <one sentence>\"" >&2; return 64; }
              date_str="$2"; shift 2 ;;
      *) [ "$have_text" = 0 ] || { echo "wrap.sh log: one text argument only" >&2; return 64; }
         text="$arg"; have_text=1; shift ;;
    esac
  done
  [ "$have_text" = 1 ] && [ -n "$text" ] || { echo "usage: wrap.sh log [--date YYYY-MM-DD] \"<slug>: <one sentence>\"" >&2; return 64; }

  # The date prefixes a line in a file the kit writes. Anything but a plain YYYY-MM-DD, a
  # second line or an out-of-range field included, refuses before any write.
  case "$date_str" in
    [0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]) ;;
    *) echo "wrap log: --date must be YYYY-MM-DD" >&2; return 1 ;;
  esac

  case "$text" in
    *$'\n'*|*$'\r'*|*$'\t'*)
      echo "wrap log: the text carries a control character; one line, no tabs" >&2; return 1 ;;
  esac
  case "$text" in
    *$'\xe2\x80\x94'*|*$'\xe2\x80\x93'*)
      echo "wrap log: the text carries an em or en dash; use a comma, a colon or a new sentence" >&2; return 1 ;;
  esac

  local line="${date_str} · ${text}"

  local target; target="$(kit_config_get_root wrap.activity_log "")"
  if [ -z "$target" ]; then
    printf '%s\n' "$line"
    echo "wrap log: no wrap.activity_log key in the kit-root kit.toml; line not written" >&2
    return 0
  fi

  case "$target" in
    "~"/*) target="${HOME}/${target#\~/}" ;;
    /*) ;;
    *) echo "wrap log: wrap.activity_log must be an absolute or ~-prefixed path, got '${target}'" >&2; return 1 ;;
  esac

  local resolved
  resolved="$(_realpath_f "$target")" || { echo "wrap log: cannot resolve '${target}'" >&2; return 1; }
  _home_fence "$resolved" "wrap log" || return 1
  [ -f "$resolved" ] || { echo "wrap log: '${resolved}' is not an existing regular file" >&2; return 1; }

  # The worktree copy is a different path, gated only by `[ -f ]`, so it gets the same
  # refusal and the same fence before anything is written to it. The refusal covers the leaf;
  # resolving the whole path covers a symlink at any parent directory, which would otherwise
  # carry the write outside HOME while the string still reads as being under the worktree.
  resolved="$(_worktree_copy "$resolved")"
  _refuse_symlink "$resolved" "wrap log" || return 1
  resolved="$(_realpath_f "$resolved")" \
    || { echo "wrap log: cannot resolve the worktree copy" >&2; return 1; }
  _home_fence "$resolved" "wrap log" || return 1
  [ -f "$resolved" ] || { echo "wrap log: '${resolved}' is not an existing regular file" >&2; return 1; }

  local n=${#line}
  [ "$n" -gt "$LOG_LINE_BUDGET" ] && echo "wrap log: note: ${n} chars, over the ${LOG_LINE_BUDGET}-char routine budget" >&2

  local head_n tmp mode; tmp="$(mktemp)"
  head_n="$(_log_anchor_head_lines "$resolved")"
  if [ "$head_n" -gt 0 ] 2>/dev/null; then
    sed -n "1,${head_n}p" "$resolved" > "$tmp"
    printf '%s\n' "$line" >> "$tmp"
    tail -n "+$((head_n + 1))" "$resolved" >> "$tmp"
  else
    printf '%s\n' "$line" > "$tmp"
    cat "$resolved" >> "$tmp"
  fi
  mode="$(_fmode "$resolved")"
  case "$mode" in ''|*[!0-7]*) mode="" ;; esac
  [ -n "$mode" ] && chmod "$mode" "$tmp"   # mktemp opens 0600; carry the target's mode over
  mv -f "$tmp" "$resolved"
  printf '%s\n' "$line"
  kit_warn_default_branch "$resolved" "wrap log"
  return 0
}

# --------------------------------------------------------------------------- knowledge-root

# cmd_knowledge_root <repo> -- prints one absolute directory and always
# exits 0: `knowledge.root` empty or any failure resolving/fencing/creating it falls back to
# `<repo>/.claude/memory`, never an error. The `<repo>` argument itself is validated (must
# exist, basename must not be `.`/`..`/empty) and THAT failure is the one case that is a
# real usage error (exit 64), since there is no repo to fall back under.
cmd_knowledge_root() {
  [ $# -eq 1 ] || { echo "usage: wrap.sh knowledge-root <repo>" >&2; return 64; }
  local repo="$1" repo_real trimmed base
  repo_real="$(cd "$repo" 2>/dev/null && pwd -P)" \
    || { echo "usage: wrap.sh knowledge-root <repo>" >&2; return 64; }
  trimmed="${repo_real%/}"
  base="${trimmed##*/}"
  case "$base" in
    .|..|"") echo "usage: wrap.sh knowledge-root <repo>" >&2; return 64 ;;
  esac

  local fallback="${repo_real}/.claude/memory"
  local root; root="$(kit_config_get_root knowledge.root "")"
  if [ -z "$root" ]; then
    printf '%s\n' "$fallback"
    return 0
  fi

  # Same `~` expansion rule cmd_log applies to wrap.activity_log.
  case "$root" in
    "~"/*) root="${HOME}/${root#\~/}" ;;
  esac

  # The dir variant of _realpath_f: `cd && pwd -P` follows every symlink on the path and
  # collapses it to the physical directory, or fails when the directory does not exist.
  local resolved
  resolved="$(cd "$root" 2>/dev/null && pwd -P)"
  if [ -z "$resolved" ]; then
    echo "knowledge-root: '${root}' is not an existing directory, using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi

  if ! _home_fence "$resolved" knowledge-root; then
    echo "knowledge-root: using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi

  # No `_write_guard` here (unlike `cmd_log`/`cmd_stage`): the only write below is `mkdir -p`
  # under `<root>/projects/<base>`, which sits OUTSIDE `$repo` entirely -- `_write_guard`
  # shells out to `git -C "$repo" rev-parse`, which fails on a non-git `<repo>` and reported
  # the misleading "index.lock held by another writer" for a directory with no lock and no git
  # dir at all. `<root>` itself is fenced above and re-fenced after the create; that is the
  # write this verb owes a guard for, and it already has one via `_home_fence`.
  #
  # Only `<root>` was fenced above. `mkdir -p` walks through a symlink at `projects` or at the
  # leaf without complaint, so both are refused before the create, and the created directory is
  # re-resolved and re-fenced after it.
  local projects="${resolved}/projects"
  local target="${projects}/${base}"
  if ! _refuse_symlink "$projects" knowledge-root || ! _refuse_symlink "$target" knowledge-root; then
    echo "knowledge-root: using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi
  if ! mkdir -p "$target" 2>/dev/null; then
    echo "knowledge-root: could not create '${target}', using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi
  local target_real
  target_real="$(cd "$target" 2>/dev/null && pwd -P)"
  if [ -z "$target_real" ] || ! _home_fence "$target_real" knowledge-root; then
    echo "knowledge-root: using ${fallback}" >&2
    printf '%s\n' "$fallback"
    return 0
  fi
  printf '%s\n' "$target_real"
  return 0
}

# --------------------------------------------------------------------------- stage

# cmd_stage "<title>" "<intent>" "<home>" [--repo <repo>] -- resolves the
# staging file the same way cmd_log resolves its target (dir realpath, symlink refusal, a
# HOME/repo fence, `_worktree_copy`), then hands the write itself to the one place the
# staging-block grammar and its dedupe rule live: `staging-format.py stage`.
cmd_stage() {
  local repo="" arg count=0
  local pos1="" pos2="" pos3=""
  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --repo)
        [ $# -ge 2 ] || {
          echo 'usage: wrap.sh stage "<title>" "<intent>" "<home>" [--repo <repo>]' >&2
          return 64
        }
        repo="$2"; shift 2 ;;
      *)
        count=$(( count + 1 ))
        case "$count" in 1) pos1="$arg" ;; 2) pos2="$arg" ;; 3) pos3="$arg" ;; esac
        shift ;;
    esac
  done
  [ "$count" -eq 3 ] || {
    echo 'usage: wrap.sh stage "<title>" "<intent>" "<home>" [--repo <repo>]' >&2
    return 64
  }
  local title="$pos1" intent="$pos2" home="$pos3"

  local repo_top
  if [ -n "$repo" ]; then
    repo_top="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null)"
  else
    repo_top="$(git rev-parse --show-toplevel 2>/dev/null)"
  fi
  [ -n "$repo_top" ] || {
    echo 'usage: wrap.sh stage "<title>" "<intent>" "<home>" [--repo <repo>]' >&2
    return 64
  }
  repo_top="$(cd "$repo_top" 2>/dev/null && pwd -P)" \
    || { echo "wrap stage: cannot resolve the repo toplevel" >&2; return 64; }

  local staging="${BACKLOG_STAGE_STAGING:-${repo_top}/_meta/backlog-staging.md}"
  local backlog="${BACKLOG_STAGE_BACKLOG:-${repo_top}/_meta/BACKLOG.md}"

  # The staging path's parent directory must resolve. Only the default parent (the repo's
  # own `_meta/`) is created on demand; an env-override parent must already exist.
  local staging_dir; staging_dir="$(dirname "$staging")"
  if [ -z "${BACKLOG_STAGE_STAGING:-}" ]; then
    mkdir -p "$staging_dir" 2>/dev/null \
      || { echo "wrap stage: cannot create ${staging_dir}" >&2; return 1; }
  fi
  local staging_dir_real
  staging_dir_real="$(cd "$staging_dir" 2>/dev/null && pwd -P)" \
    || { echo "wrap stage: '${staging_dir}' does not resolve" >&2; return 1; }

  local leaf; leaf="$(basename "$staging")"
  local resolved="${staging_dir_real%/}/${leaf}"

  # Never a symlink; absent or an existing regular file only.
  _refuse_symlink "$resolved" "wrap stage" || return 1
  if [ -e "$resolved" ] && [ ! -f "$resolved" ]; then
    echo "wrap stage: '${resolved}' is not a regular file" >&2; return 1
  fi

  # Inside the repo toplevel by default; under HOME when the env override chose the path. The
  # override comes from the environment, which a repo `.envrc` writes, so it may only append to
  # a file that already exists: create-on-absent under HOME would let it seed a new block into
  # any absent path, an agent instruction file included. Only the repo default creates.
  if [ -n "${BACKLOG_STAGE_STAGING:-}" ]; then
    _home_fence "$resolved" "wrap stage" || return 1
    [ -f "$resolved" ] \
      || { echo "wrap stage: '${resolved}' is not an existing regular file" >&2; return 1; }
  else
    case "$resolved" in
      "$repo_top"/*) ;;
      *) echo "wrap stage: '${resolved}' is outside the repo (${repo_top})" >&2; return 1 ;;
    esac
  fi

  if ! _write_guard "$repo_top"; then
    echo "wrap stage: index.lock held by another writer" >&2; return 1
  fi

  # The worktree copy is a path none of the checks above saw, and `_worktree_copy` gates it
  # only with `[ -f ]`, which follows a symlink. Re-run the refusal and the fence on it. The
  # refusal covers the leaf; resolving the whole path covers a symlink at any parent directory
  # (`<worktree>/_meta` pointing off disk), which the prefix rules below would otherwise pass
  # because the unresolved string still starts with the worktree toplevel.
  local pre_copy="$resolved"
  resolved="$(_worktree_copy "$resolved")"
  if [ "$resolved" != "$pre_copy" ]; then
    _refuse_symlink "$resolved" "wrap stage" || return 1
    resolved="$(_realpath_f "$resolved")" \
      || { echo "wrap stage: cannot resolve the worktree copy" >&2; return 1; }
    [ -f "$resolved" ] \
      || { echo "wrap stage: '${resolved}' is not a regular file" >&2; return 1; }
    if [ -n "${BACKLOG_STAGE_STAGING:-}" ]; then
      _home_fence "$resolved" "wrap stage" || return 1
    else
      # The copy lives in the CURRENT worktree, which is a different toplevel of the same repo.
      # Both toplevels are compared as realpaths, matching the resolved copy.
      local cur_top
      cur_top="$(git rev-parse --show-toplevel 2>/dev/null)" \
        && cur_top="$(cd "$cur_top" 2>/dev/null && pwd -P)"
      case "$resolved" in
        "$repo_top"/*) ;;
        "${cur_top:-/dev/null/never}"/*) ;;
        *) echo "wrap stage: '${resolved}' is outside the repo (${repo_top})" >&2; return 1 ;;
      esac
    fi
  fi

  [ -f "$STAGING_FORMAT_PY" ] \
    || { echo "wrap stage: staging-format.py missing at ${STAGING_FORMAT_PY}" >&2; return 1; }

  # Build the JSON with sys.argv, never string interpolation: title/intent/home are
  # session text and must never be able to forge a stdin field.
  python3 -c '
import json, sys
title, intent, home, staging, backlog = sys.argv[1:6]
json.dump(
    {"title": title, "intent": intent, "home": home, "staging": staging, "backlog": backlog},
    sys.stdout,
)
' "$title" "$intent" "$home" "$resolved" "$backlog" \
    | python3 "$STAGING_FORMAT_PY" stage
  local rc=$?
  if [ "$rc" -eq 0 ]; then kit_warn_default_branch "$resolved" "wrap stage"; fi
  return "$rc"
}

