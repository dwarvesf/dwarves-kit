# wrap-land.sh -- the land verb and its helpers; sourced by lib/wrap/wrap.sh.


# _tree_verify <repo> <def> <head_oid> <merge_oid> -- "OK", "MISMATCH <n>", or
# "UNVERIFIABLE <reason>". Proves the merge commit gh named sits on the default branch and
# applied exactly the PR's net change: for every path either side touched, the merge
# commit's own diff equals the PR's diff from its merge-base. Whole trees are not compared,
# because a PR that landed on the default branch in between is not the mismatch this guards.
_tree_verify() {
  local repo="$1" def="$2" head_oid="$3" merge_oid="$4" tip parent base p n=0
  git -C "$repo" fetch -q origin "$def" 2>/dev/null || { echo "UNVERIFIABLE fetch of ${def} failed"; return; }
  tip="$(git -C "$repo" rev-parse "origin/${def}" 2>/dev/null)"
  [ -n "$tip" ] || { echo "UNVERIFIABLE origin/${def} did not resolve"; return; }
  git -C "$repo" cat-file -e "${head_oid}^{commit}" 2>/dev/null || {
    echo "UNVERIFIABLE the PR head is not a local object"; return; }
  [ -n "$merge_oid" ] && git -C "$repo" cat-file -e "${merge_oid}^{commit}" 2>/dev/null || {
    echo "UNVERIFIABLE the merge commit ${merge_oid:-gh did not name} is not a local object"; return; }
  git -C "$repo" merge-base --is-ancestor "$merge_oid" "$tip" 2>/dev/null || {
    echo "UNVERIFIABLE the merge commit $(_short "$merge_oid") is not on origin/${def}"; return; }
  if [ "$(git -C "$repo" rev-parse "${merge_oid}^{tree}" 2>/dev/null)" = \
       "$(git -C "$repo" rev-parse "${head_oid}^{tree}" 2>/dev/null)" ]; then
    echo "OK"; return
  fi
  parent="$(git -C "$repo" rev-parse -q --verify "${merge_oid}^1" 2>/dev/null)"
  [ -n "$parent" ] || { echo "UNVERIFIABLE the merge commit has no parent"; return; }
  base="$(git -C "$repo" merge-base "$head_oid" "$parent" 2>/dev/null)"
  [ -n "$base" ] || { echo "UNVERIFIABLE no common history with ${def}"; return; }
  [ -n "$(git -C "$repo" diff-tree -r --name-only "$base" "$head_oid" 2>/dev/null)" ] || {
    echo "UNVERIFIABLE the PR touched no path git can name"; return; }
  while IFS= read -r -d '' p; do
    [ "$(_path_change "$repo" "$base" "$head_oid" "$p")" = \
      "$(_path_change "$repo" "$parent" "$merge_oid" "$p")" ] || n=$((n + 1))
  done < <({ git -C "$repo" diff-tree -r -z --no-renames --name-only "$base" "$head_oid"
             git -C "$repo" diff-tree -r -z --no-renames --name-only "$parent" "$merge_oid"; } 2>/dev/null | sort -zu)
  if [ "$n" -eq 0 ]; then echo "OK"; else echo "MISMATCH ${n}"; fi
}

# _path_change <repo> <from> <to> <path> -- one path's change as a zero-context patch with
# the index and hunk-position lines dropped, so the same edit made on top of a file another
# PR also changed compares equal, while any difference in the added or removed lines does not.
_path_change() {
  git -C "$1" diff-tree -p -U0 --no-renames --binary "$2" "$3" -- ":(literal)$4" 2>/dev/null \
    | grep -v -e '^index ' -e '^@@ '
}

# _land_feature_title <wt> <def> -- the branch's feature-commit subject, for `land`'s
# no-`--title` default. Walks non-merge commits ahead of `origin/<def>`, oldest first
# (`--topo-order`, so a merged-in side commit with an older date never sorts ahead of the
# branch's own first commit), and picks the first whose subject is not a `docs`/`chore`/`test`
# conventional type. Falls back to the oldest non-merge commit ahead when every one is
# housekeeping. Never combines `--reverse` with `-1`/`-n1`: git applies a count limit BEFORE
# reversing, so that would silently return the newest commit instead of the oldest -- the walk
# reads the full list and takes the first line in the shell instead.
_land_feature_title() {
  local wt="$1" def="$2" s
  while IFS= read -r s; do
    printf '%s\n' "$s" | grep -qE '^(docs|chore|test)(\([^)]*\))?!?:' || { printf '%s\n' "$s"; return 0; }
  done < <(git -C "$wt" log --no-merges --topo-order --format=%s --reverse "origin/${def}..HEAD" 2>/dev/null)
  git -C "$wt" log --no-merges --topo-order --format=%s --reverse "origin/${def}..HEAD" 2>/dev/null | head -1
}

# _pr_template <wt> -- the repo's GitHub PR template (path relative to <wt>), empty when it
# has none. File names match case-insensitively, as GitHub reads them.
_pr_template() {
  local wt="$1" d f
  for d in .github . docs; do
    f="$(find "$wt/$d" -maxdepth 1 -type f -iname 'pull_request_template.md' 2>/dev/null | sed -n 1p)"
    [ -n "$f" ] && { printf '%s\n' "${f#"$wt"/}"; return 0; }
  done
  return 1
}

# _rollup_failed_checks <statusCheckRollup json> -- the names of the checks whose latest run
# ended red, comma-joined, empty when none did. Latest run per name wins, the same dedupe
# _pr_gate applies.
_rollup_failed_checks() {
  printf '%s' "$1" | jq -r "${CI_JQ_DEFS}"'
    def rtime: [.completedAt, .startedAt, .createdAt] | map(real) | .[0] // "";
    ((.statusCheckRollup // [])
      | group_by(.name // .context)
      | map(sort_by([(if pending then 1 else 0 end), rtime]) | last)
      | map(select(((.conclusion // .state // "") | ascii_upcase) as $c
            | $c == "FAILURE" or $c == "ERROR" or $c == "CANCELLED" or $c == "TIMED_OUT")
          | (.name // .context // "check")) | join(", "))' 2>/dev/null
}

# _land_pr_checks_gate <wt> <repo-url> <pr> -- before the first merge, let the PR's checks
# report and refuse a red one. A check opened seconds ago has not registered yet, and
# `gh pr merge` does not wait for it, so the merge beat the check and the failure only
# emailed afterwards. A repo with no `pull_request` workflow pays nothing. The wait is the
# ci wait with a short registration grace (KIT_WRAP_LAND_GRACE_SECS) and the usual completion
# bound (KIT_WRAP_CARRY_CHECKS_SECS). Under `--with-ci` that wait already ran, so only the
# verdict is read. Returns 2 with the PR left open.
# The registration grace has two sizes. GitHub queued the `pull_request` run of share#47 190s
# after the PR opened, so 30s merged ahead of it. A workflow that is sure to run on every PR
# (a `pull_request` trigger key, not the word inside an `if:`, with no `paths`/`labeled` filter) holds to
# KIT_WRAP_LAND_REGISTER_SECS; a filtered one may legitimately start nothing, so it keeps
# the short KIT_WRAP_LAND_GRACE_SECS. The wait ends at the first check that appears, so the
# long bound costs nothing when GitHub is quick.
# ponytail: the workflow test is a plain grep, so a commented-out trigger still arms the wait
# and a `paths:` under `push:` reads as a filter on the PR; parse the `on:` block if it matters.
KIT_WRAP_LAND_GRACE_SECS=${KIT_WRAP_LAND_GRACE_SECS:-30}
case "$KIT_WRAP_LAND_GRACE_SECS" in ''|*[!0-9]*) KIT_WRAP_LAND_GRACE_SECS=30 ;; esac
KIT_WRAP_LAND_REGISTER_SECS=${KIT_WRAP_LAND_REGISTER_SECS:-300}
case "$KIT_WRAP_LAND_REGISTER_SECS" in ''|*[!0-9]*) KIT_WRAP_LAND_REGISTER_SECS=300 ;; esac
_land_unfiltered_pr_workflow() {
  local f
  for f in "$1"/.github/workflows/*.y*ml; do
    [ -f "$f" ] || continue
    grep -qE '^[[:space:]]*(pull_request(_target)?:|-[[:space:]]*pull_request)|^on:.*pull_request' "$f" || continue
    grep -qE '^[[:space:]]*paths(-ignore)?:|labeled' "$f" || return 0
  done
  return 1
}
_land_pr_checks_gate() {
  local wt="$1" url="$2" n="$3" proll pnum failed
  grep -rqE 'pull_request' "$wt/.github/workflows" 2>/dev/null || return 0
  if ! _ci_on_merge; then
    CI_PRELABEL_KEYS='[]'
    local KIT_WRAP_CI_GRACE_SECS="$KIT_WRAP_LAND_GRACE_SECS"
    _land_unfiltered_pr_workflow "$wt" && KIT_WRAP_CI_GRACE_SECS="$KIT_WRAP_LAND_REGISTER_SECS"
    _ci_checks_wait "$url" "$n"
    [ "${CI_WAIT_END:-}" = "NONEW" ] && [ "$KIT_WRAP_CI_GRACE_SECS" = "$KIT_WRAP_LAND_REGISTER_SECS" ] \
      && echo "     no checks registered on #${n} after ${KIT_WRAP_CI_GRACE_SECS}s; merging with none" >&2
  fi
  proll="$(gh pr view "$n" --repo "$url" --json statusCheckRollup 2>/dev/null)" \
    && printf '%s' "$proll" | jq -e . >/dev/null 2>&1 || {
    echo "     MERGE REFUSED #${n}: its checks are unreadable; PR left open" >&2; return 2; }
  pnum="$(printf '%s' "$proll" | jq -r "${CI_JQ_DEFS} ([.statusCheckRollup // [] | .[] | select(pending)] | length)" 2>/dev/null)"
  if [ "$pnum" != "0" ]; then
    echo "     MERGE REFUSED #${n}: checks still pending after ${KIT_WRAP_CARRY_CHECKS_SECS}s; PR left open" >&2; return 2
  fi
  failed="$(_rollup_failed_checks "$proll")"
  if [ -n "$failed" ]; then
    echo "     MERGE REFUSED #${n}: checks failed: ${failed}; PR left open" >&2; return 2
  fi
}

# _land_proof_files <wt> <base> -- the proof-of-done files the branch added or changed that
# are still in the tree, one repo-relative path per line. The lookup is the ship-gate's own
# (proof-ledger.sh proof-files); any failure reads as "no proof file".
_land_proof_files() {
  local f
  bash "$PROOF_LEDGER_SH" proof-files "$1" "$2" 2>/dev/null | while IFS= read -r f; do
    [ -f "$1/$f" ] && printf '%s\n' "$f"
  done
}

# _land_web_url <origin url> -- the repository's https page, empty when origin is not a
# hosted remote (a local path has no page to link).
_land_web_url() {
  local u="${1%.git}"
  case "$u" in
    https://*) printf '%s\n' "$u" ;;
    ssh://git@*) printf 'https://%s\n' "${u#ssh://git@}" ;;
    git@*:*) u="${u#git@}"; printf 'https://%s/%s\n' "${u%%:*}" "${u#*:}" ;;
  esac
}

# _land_proof_body <wt> <base> <title> <head sha> <origin url> -- the PR body `land` writes
# when the caller gave none: the title as a one-line summary, then `## Proof of done` with
# each proof file's content, so the captured output is in the PR and not only in the tree.
# A relative image link that resolves in the tree becomes an absolute URL pinned to the head
# sha, because a PR body renders no repo-relative path. Prints nothing when the branch has
# no proof file. Cut at _LAND_BODY_MAX characters (GitHub refuses a body over 65536), ending
# on a pointer to the file.
_LAND_BODY_MAX=40000
_land_proof_body() {
  local wt="$1" base="$2" title="$3" sha="$4" web files f text link path body
  web="$(_land_web_url "$5")"
  files="$(_land_proof_files "$wt" "$base")"
  [ -n "$files" ] || return 0
  body="${title}"$'\n\n'"## Proof of done"
  while IFS= read -r f; do
    text="$(cat "$wt/$f")"
    if [ -n "$web" ]; then
      while IFS=$'\t' read -r link path; do
        [ -n "$link" ] || continue
        case "$path" in
          .kit/proof-assets/*)
            # A local-mode cache link resolves to a file that exists only in the
            # worktree: rewriting it to a blob URL would link a page that can never
            # exist, so the body names it instead.
            text="$(printf '%s\n' "$text" | sed -E "s/!\[[^]]*\]\($(printf '%s' "$link" | sed -E 's/[][(){}|&*+.^$?\\/]/\\&/g')\)/_(local image, not uploaded: ${path##*/})_/g")"
            continue ;;
        esac
        link="](${link})"; path="](${web}/blob/${sha}/${path}?raw=true)"
        text=${text//"$link"/"$path"}
      done < <(bash "$PROOF_LEDGER_SH" images "$wt/$f" "$wt" 2>/dev/null)
    fi
    body="${body}"$'\n\n'"From \`${f}\`:"$'\n\n'"${text}"
  done <<< "$files"
  if [ "${#body}" -gt "$_LAND_BODY_MAX" ]; then
    body="${body:0:$_LAND_BODY_MAX}"
    # A cut inside a fenced block would render the pointer as code: close the fence first.
    [ $(( $(printf '%s\n' "$body" | grep -cE '^[[:space:]]*(```|~~~)') % 2 )) -eq 0 ] || body="${body}"$'\n''```'
    body="${body}"$'\n\n'"[cut at ${_LAND_BODY_MAX} characters; the full proof is in $(printf '%s\n' "$files" | sed "s|^|${web:+${web}/blob/${sha}/}|" | paste -sd ' ' -)]"
  fi
  printf '%s\n' "$body"
}

# _land_proof_block <wt> <base> <pr> -- the operator's view of the proof, printed last by a
# successful land: the proof file, the PR, and what the run printed (the `Output:` lines, at
# most _LAND_BLOCK_LINES per file), or the committed images when the proof is a capture.
# Prints nothing when the branch has no proof file.
_LAND_BLOCK_LINES=15
_land_proof_block() {
  local wt="$1" base="$2" pr="$3" files f out
  files="$(_land_proof_files "$wt" "$base")"
  [ -n "$files" ] || return 0
  echo "PROOF OF DONE"
  printf '%s\n' "$files" | sed 's/^/  proof: /'
  echo "  PR:    ${pr}"
  while IFS= read -r f; do
    out="$(bash "$PROOF_LEDGER_SH" captured-output "$wt/$f" 2>/dev/null | head -n "$_LAND_BLOCK_LINES")"
    [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/    | /'
    bash "$PROOF_LEDGER_SH" images "$wt/$f" "$wt" 2>/dev/null | cut -f2 | sed 's/^/    image: /'
  done <<< "$files"
}

# --------------------------------------------------------------------------- land

# _LAND_IGNORED_BUILTIN -- ignored entries the guard always allows: build output, tool caches,
# local config that must never be committed, and the kit's own state. Space-separated, three
# forms (see _land_ignored_allowed). `*` in a path form crosses `/`, which is fine here.
_LAND_IGNORED_BUILTIN="node_modules .wrangler dist *.tsbuildinfo __pycache__ target .pytest_cache/ .venv/ .mypy_cache/ .ruff_cache/ .env .env.* .envrc .dev.vars .DS_Store .claude/session-state tests/.cache lib/*/bin/*-rs"

# _land_ignored_allowed <path> -- 0 when the built-in list or the operator's
# wrap.land_ignored_allow covers <path> (a `git status` entry, trailing `/` already
# stripped). Forms: no `/` globs the LAST component only, never an ancestor; a trailing `/`
# allows the whole subtree under any directory of that name; any other entry with a `/`
# globs the whole path or a leading run of its components. Split under set -f so an entry
# such as `*.json` never expands against the cwd.
_land_ignored_allowed() {
  local p="$1" entries entry name last prefix part comp rest restore="" hit=1
  case "$-" in *f*) ;; *) restore=1; set -f ;; esac
  entries="${_LAND_IGNORED_BUILTIN} $(kit_config_get_root wrap.land_ignored_allow "")"
  last="${p##*/}"
  for entry in $entries; do
    case "$entry" in
      */)
        name="${entry%/}"
        case "$name" in
          */*) entry="$name" ;;
          *) rest="$p"
             while :; do
               comp="${rest%%/*}"
               # shellcheck disable=SC2254
               case "$comp" in $name) hit=0; break ;; esac
               case "$rest" in */*) rest="${rest#*/}" ;; *) break ;; esac
             done
             [ "$hit" -eq 0 ] && break
             continue ;;
        esac ;;
      */*) ;;
      *) # shellcheck disable=SC2254
         case "$last" in $entry) hit=0; break ;; esac
         continue ;;
    esac
    prefix=""; rest="$p"
    while :; do
      part="${rest%%/*}"
      prefix="${prefix:+${prefix}/}${part}"
      # shellcheck disable=SC2254
      case "$prefix" in $entry) hit=0; break ;; esac
      case "$rest" in */*) rest="${rest#*/}" ;; *) break ;; esac
    done
    [ "$hit" -eq 0 ] && break
  done
  [ -z "$restore" ] || set +f
  return "$hit"
}

# _land_symlink_outside <wt> <path> -- 0 when <wt>/<path> is a symlink whose resolved target
# lies outside the worktree. A worktree-setup step links shared build output (an `out/`) in
# from the main checkout; removing the worktree drops the link and leaves the target alone,
# so the guard has nothing to protect. A real file or dir, an in-tree link, and a link that
# cannot be resolved all return 1 (fail closed).
_land_symlink_outside() {
  local wt="$1" p="$2" wt_real tgt
  [ -L "$wt/$p" ] || return 1
  wt_real="$(cd "$wt" 2>/dev/null && pwd -P)" || return 1
  tgt="$(_realpath_f "$wt/$p")" || return 1
  case "$tgt" in "$wt_real"|"$wt_real"/*) return 1 ;; esac
  return 0
}

# _land_ignored_guard <wt> <base> <branch> -- refuse (return 1, print the paths) when the
# worktree holds a gitignored file under a directory the branch touches: tests that read it
# pass here and fail on a clean checkout, and git does not count an ignored file as dirty.
# Scope per touched path: a root file scopes the root's direct children; a depth-1 file
# (_meta/x) scopes that directory's direct children; depth 2 or more (tools/x/t/a) scopes the
# first two components' whole subtree. Every read fails closed. Writes nothing.
# ponytail: a fixture outside every scope (a root-level test reading testdata/x, a depth-1
# test reading a grandchild) is not seen; the scope rule is a heuristic, not a dependency scan.
_land_ignored_guard() {
  local wt="$1" base="$2" branch="$3"
  local fail="     LAND REFUSED: the ignored-file check could not read"
  if [ -z "$base" ]; then
    echo "${fail} the merge base; nothing pushed" >&2; return 1
  fi
  local diff_out diff_rc
  diff_out="$(git -C "$wt" diff --name-only -z --no-renames "$base" HEAD 2>/dev/null \
    | tr '\0' '\001'; exit "${PIPESTATUS[0]}")"; diff_rc=$?
  if [ "$diff_rc" -ne 0 ]; then
    echo "${fail} git diff; nothing pushed" >&2; return 1
  fi

  local scopes=$'\n' root_scope=0 path dir rest
  local -a specs=()
  while IFS= read -r -d $'\001' path; do
    [ -n "$path" ] || continue
    # The scope list is newline-separated, so a newline in a name would split its scope.
    case "$path" in *$'\n'*)
      echo "     LAND REFUSED: a touched path holds a newline, so the ignored-file check cannot scope it; nothing pushed" >&2; return 1 ;;
    esac
    case "$path" in
      */*/*) dir="${path%%/*}"; rest="${path#*/}"; dir="${dir}/${rest%%/*}"
             case "$scopes" in *$'\n'"s:${dir}"$'\n'*) ;; *) scopes="${scopes}s:${dir}"$'\n'; specs+=(":(literal)${dir}") ;; esac ;;
      */*)   dir="${path%%/*}"
             case "$scopes" in *$'\n'"d:${dir}"$'\n'*) ;; *) scopes="${scopes}d:${dir}"$'\n'; specs+=(":(literal)${dir}") ;; esac ;;
      *)     root_scope=1 ;;
    esac
  done <<< "$diff_out"
  if [ "$root_scope" -eq 0 ] && [ "${#specs[@]}" -eq 0 ]; then return 0; fi
  # A root scope cannot be named by a pathspec, so it reads the whole tree; the prefix
  # filter below is the authority either way.
  [ "$root_scope" -eq 0 ] || specs=()

  local st st_rc
  st="$(git -C "$wt" status --porcelain -z --ignored=matching --untracked-files=normal \
    ${specs[@]+-- "${specs[@]}"} 2>/dev/null | tr '\0' '\001'; exit "${PIPESTATUS[0]}")"; st_rc=$?
  if [ "$st_rc" -ne 0 ]; then
    echo "${fail} git status; nothing pushed" >&2; return 1
  fi

  local ent e p rel sc found lines="" n=0 marked=0 base_name safe
  while IFS= read -r -d $'\001' ent; do
    case "$ent" in '!! '*) ;; *) continue ;; esac
    e="${ent#!! }"
    p="${e%/}"
    found=0
    # Literal prefix compare, never a glob or regex.
    if [ "$root_scope" -eq 1 ]; then
      case "$p" in */*) ;; *) found=1 ;; esac
    fi
    if [ "$found" -eq 0 ]; then
      while IFS= read -r sc; do
        [ -n "$sc" ] || continue
        dir="${sc#?:}"
        case "$p" in "${dir}/"*) ;; *) continue ;; esac
        rel="${p#"${dir}"/}"
        case "${sc%%:*}" in
          s) found=1 ;;
          d) case "$rel" in */*) ;; *) found=1 ;; esac ;;
        esac
        [ "$found" -eq 0 ] || break
      done <<< "$scopes"
    fi
    [ "$found" -eq 1 ] || continue
    ! _land_ignored_allowed "$p" || continue
    ! _land_symlink_outside "$wt" "$p" || continue
    safe="$(printf '%s' "$e" | tr '[:cntrl:]' '?')"
    base_name="$(printf '%s' "${p##*/}" | tr 'A-Z' 'a-z')"
    case "$base_name" in
      .env*|*.pem|*.key|*secret*|*credential*|*token*)
        safe="${safe}  (looks like a secret: never commit; move or delete it, or allow it)"
        marked=$(( marked + 1 )) ;;
    esac
    lines="${lines}${safe}"$'\n'
    n=$(( n + 1 ))
  done <<< "$st"
  [ "$n" -gt 0 ] || return 0

  echo "     LAND REFUSED: ${n} ignored path$([ "$n" -eq 1 ] || echo s) under what ${branch} touches; a clean checkout will not have $([ "$n" -eq 1 ] && echo it || echo them)" >&2
  printf '%s' "$lines" | env LC_ALL=C sort | head -n 20 | sed 's/^/       /' >&2
  [ "$n" -le 20 ] || echo "       and $(( n - 20 )) more" >&2
  if [ "$marked" -lt "$n" ]; then
    echo "     a human decides for each unmarked path: commit it (git add -f), delete it, or allow it in [wrap] land_ignored_allow in the operator kit.toml" >&2
  fi
  return 1
}

# cmd_land <worktree> [--title T] [--body-file F] [--no-pull] [--with-ci] [--verify C] [--draft] -- the landing loop for ONE committed
# branch in a hand-made worktree: push, open the PR, squash-merge, verify the tree, fast
# forward the main checkout, remove the worktree, delete the branch. Each step prints one
# line with its sha or its refusal. With no --body-file the PR body is the branch's proof of
# done (_land_proof_body), and a land that merged ends on a PROOF OF DONE block.
#
# The composition is deliberate. The push names its branch, because a bare push takes
# whatever the upstream config points at. The merge is its own command, because chaining a
# branch delete behind a failed merge closes the PR and drops its commits. The tree check
# is `merge`'s own `_tree_verify`, never a second copy. Nothing here logs a proof-ledger
# override: a ship-gate refusal on the push surfaces with the gate's own stderr and exit
# code, and the run stops there.
#
# --draft stops the loop at the open: after the same pre-push refusals (plus an already-landed
# branch, an open non-draft PR, a new PR with no proof and no --body-file, and the ship-gate
# hook) it pushes, opens or adopts a DRAFT PR, prints the URL and the proof block, and returns.
# It never marks the PR ready, merges, tidies, pulls or writes a Ship record; the worktree stays.
cmd_land() {
  local wt="" title="" body_file="" verify="" arg count=0 want="" flags_given=0
  local draft=0 with_ci_given=0 verify_given=0 nopull_given=0
  NO_PULL=0
  for arg in "$@"; do
    if [ -n "$want" ]; then
      case "$want" in title) title="$arg" ;; body) body_file="$arg" ;; verify) verify="$arg" ;; esac
      want=""; continue
    fi
    case "$arg" in
      --title) want=title; flags_given=1 ;;
      --title=*) title="${arg#--title=}"; flags_given=1 ;;
      --body-file) want=body; flags_given=1 ;;
      --body-file=*) body_file="${arg#--body-file=}"; flags_given=1 ;;
      --verify) want=verify; verify_given=1 ;;
      --verify=*) verify="${arg#--verify=}"; verify_given=1 ;;
      --with-ci) KIT_WRAP_CI_ON_MERGE=1; with_ci_given=1 ;;
      --no-pull) NO_PULL=1; nopull_given=1 ;;
      --draft) draft=1 ;;
      -*) echo "wrap.sh land: unknown flag '$arg'" >&2; return 64 ;;
      *) _reject_packed land "$arg" || return 64
         count=$(( count + 1 )); wt="$arg" ;;
    esac
  done
  [ -z "$want" ] || { echo "wrap.sh land: --${want} needs a value" >&2; return 64; }
  # --draft never merges or tidies, so the flags that only steer those would be silently dead.
  if [ "$draft" -eq 1 ]; then
    [ "$with_ci_given" -eq 0 ] || { echo "wrap.sh land: --draft cannot combine with --with-ci" >&2; return 64; }
    [ "$verify_given" -eq 0 ] || { echo "wrap.sh land: --draft cannot combine with --verify" >&2; return 64; }
    [ "$nopull_given" -eq 0 ] || { echo "wrap.sh land: --draft cannot combine with --no-pull" >&2; return 64; }
  fi
  [ "$count" -eq 1 ] || { echo "usage: wrap.sh land <worktree> [--title T] [--body-file F] [--with-ci] [--no-pull] [--verify <cmd>] [--draft]" >&2; return 64; }
  _is_repo "$wt" || { echo "wrap.sh land: ${wt} is not a git worktree" >&2; return 64; }
  if [ -n "$body_file" ] && [ ! -f "$body_file" ]; then
    echo "wrap.sh land: --body-file '${body_file}' is not an existing file" >&2; return 64
  fi
  # git records a worktree fully resolved, so the postcondition below can only match a
  # path resolved the same way.
  wt="$(cd "$wt" 2>/dev/null && pwd -P)" || { echo "wrap.sh land: the worktree path does not resolve" >&2; return 64; }

  local repo; repo="$(git -C "$wt" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  repo="${repo%/.git}"; repo="${repo%/}"
  repo="$(cd "$repo" 2>/dev/null && pwd -P)" || { echo "wrap.sh land: the main checkout does not resolve" >&2; return 64; }
  if [ "$repo" = "$wt" ]; then
    echo "wrap.sh land: ${wt} is the main checkout, not a worktree" >&2; return 1
  fi

  # The visual-proof flush (opt-in via proof.visual): the branch's proof-asset manifests can
  # hold entries an offline `put` left pending, so they flush here, inside the worktree
  # being landed, before the dirty check and before the push. The flag reads from the
  # worktree's own .kit.toml because the manifests it governs live on this branch. The
  # flush commits nothing; a non-zero exit stops the land on the flush's own message.
  if [ "$(KIT_PROJECT_ROOT="$wt" kit_config_get proof.visual false)" = "true" ]; then
    local flush_out flush_rc
    flush_out="$(cd "$wt" && "${PROOF_ASSET_BIN:-$LIB_ROOT/../bin/proof-asset}" flush 2>&1)" \
      && flush_rc=0 || flush_rc=$?
    [ -z "$flush_out" ] || printf '%s\n' "$flush_out"
    if [ "$flush_rc" -ne 0 ]; then
      echo "     LAND REFUSED: proof-asset flush exited ${flush_rc}" >&2
      return "$flush_rc"
    fi
  fi

  # One read serves both the clean check and the baseline _land_tidy needs: what the
  # pre-merge ignore rules cover, written as the `??` lines it shows once a merge un-ignores
  # it. That file is the operator's, not a write made since, and it is the only difference
  # the pre-removal recheck tolerates on the merge path.
  local st0 base_ignored
  st0="$(git -C "$wt" status --porcelain --ignored=matching 2>/dev/null)"
  if [ -n "$(printf '%s\n' "$st0" | grep -v '^!! ')" ]; then
    echo "wrap.sh land: ${wt} is dirty, so the branch is not what a PR would carry" >&2; return 1
  fi
  base_ignored="$(printf '%s\n' "$st0" | sed -n 's/^!! /?? /p')"
  local branch; branch="$(git -C "$wt" branch --show-current 2>/dev/null)"
  [ -n "$branch" ] || { echo "wrap.sh land: ${wt} is on a detached HEAD, so there is no branch to land" >&2; return 1; }
  local def; def="$(_default_branch "$wt")" || { echo "wrap.sh land: no default branch resolved for ${wt}" >&2; return 1; }
  case "$branch" in
    "$def"|main|master)
      echo "wrap.sh land: HEAD is ${branch}, the default or a protected branch name" >&2; return 1 ;;
  esac
  local ghs; ghs="$(_gh_state)"
  [ "$ghs" = "ok" ] || { echo "wrap.sh land: gh is ${ghs}" >&2; return 1; }

  # Full refs, as _merge_proof reads them: a tag or local branch named like origin/<def> or
  # the branch resolves first as a short name, so the count and the proof could disagree.
  local fetch_ok=0
  git -C "$wt" fetch -q origin "$def" 2>/dev/null || fetch_ok=1
  local ahead; ahead="$(git -C "$wt" rev-list --count "refs/remotes/origin/${def}..refs/heads/${branch}" 2>/dev/null)"
  case "$ahead" in ''|*[!0-9]*) ahead=0 ;; esac
  [ "$ahead" -gt 0 ] || {
    echo "wrap.sh land: ${branch} has no commits ahead of origin/${def}" >&2; return 1; }

  local tip url rc
  tip="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
  url="$(_origin_url "$wt")"
  [ -n "$title" ] || title="$(_land_feature_title "$wt" "$def")"
  # The branch's proof of done, for the PR body and the closing block. Read once, before the
  # push: the tidy removes the worktree. No proof file leaves both empty and land as it was.
  local proof_base proof_body=""
  proof_base="$(git -C "$wt" merge-base "refs/remotes/origin/${def}" "refs/heads/${branch}" 2>/dev/null)"
  [ -z "$proof_base" ] || [ -n "$body_file" ] || proof_body="$(_land_proof_body "$wt" "$proof_base" "$title" "$tip" "$url")"

  echo "land ${branch} -> ${def} (${wt})"

  # A full-lane run opens the PR before land runs (evidence, review), so land checks for
  # that PR first: `gh pr create` on an already-open branch just refuses. Fork entries
  # (isCrossRepository) are dropped before counting, so a fork's same-named branch never
  # counts as the operator's own open PR.
  local open_json openrc
  open_json="$(gh pr list --repo "$url" --head "$branch" --state open \
    --json number,baseRefName,author,isDraft,isCrossRepository,title,body,url 2>/dev/null)"; openrc=$?
  if [ "$openrc" -ne 0 ]; then
    echo "     PR REFUSED: open-PR lookup for ${branch} failed" >&2; return 2
  fi
  # A lookup gh answered with unparseable JSON is a failed lookup, never "no open PR".
  open_json="$(printf '%s' "$open_json" | jq -c '[.[] | select((.isCrossRepository // false) | not)]' 2>/dev/null)" || {
    echo "     PR REFUSED: open-PR lookup for ${branch} failed" >&2; return 2; }
  local open_count; open_count="$(printf '%s' "$open_json" | jq -r 'length' 2>/dev/null)"
  case "$open_count" in ''|*[!0-9]*)
    echo "     PR REFUSED: open-PR lookup for ${branch} failed" >&2; return 2 ;;
  esac

  # The branch's content may already be on the default branch by another route: a squash
  # merge writes a new commit, so `ahead` stays above zero and the branch looks unlanded. The
  # ancestor route cannot fire here (ahead > 0 above), so an ancestor-shaped proof is dropped
  # rather than acted on. A failed fetch proves nothing either way, so it skips the check.
  local proof=""
  if [ "$fetch_ok" -eq 0 ]; then
    proof="$(_merge_proof "$repo" "$def" "$ghs" "$branch")" || proof=""
    case "$proof" in ancestor*) proof="" ;; esac
  fi
  if [ -n "$proof" ]; then
    if [ "$draft" -eq 1 ]; then
      echo "     DRAFT REFUSED: ${branch} is already landed (${proof}); nothing to review" >&2; return 2
    fi
    # The proof can cost a network round trip: the tree and tip it judged must still be the
    # ones on disk.
    if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ] \
       || [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$tip" ]; then
      echo "     LAND REFUSED: ${branch} changed while the merge proof was read" >&2; return 2
    fi
    # The proof is about the LOCAL tip. Origin's copy must be absent or the same commit; a
    # failed read proves nothing, so it refuses (exit 2 of --exit-code is the only "absent").
    local ls_out ls_rc origin_probe osha
    ls_out="$(git -C "$wt" ls-remote --exit-code origin "refs/heads/${branch}" 2>&1)"; ls_rc=$?
    case "$ls_rc" in
      2) origin_probe=absent ;;
      0) # ls-remote matches the pattern as a path suffix, so a tag named
         # refs/tags/refs/heads/<branch> is listed too: only the exact ref counts, and two
         # lines for it is an answer nothing can trust.
         local exact nexact
         exact="$(printf '%s\n' "$ls_out" | awk -F'\t' -v r="refs/heads/${branch}" '$2 == r')"
         nexact="$(printf '%s\n' "$exact" | grep -c .)"
         if [ "$nexact" -gt 1 ]; then
           echo "     LAND REFUSED: origin/${branch} could not be confirmed: ${ls_out}" >&2; return 2
         elif [ "$nexact" -eq 0 ]; then origin_probe=absent
         else
           osha="$(printf '%s' "$exact" | cut -f1)"
           if [ "$osha" = "$tip" ]; then origin_probe=present
           else
             echo "     LAND REFUSED: origin/${branch} ($(_short "$osha")) differs from the proven $(_short "$tip")" >&2
             return 2
           fi
         fi ;;
      *) echo "     LAND REFUSED: origin/${branch} could not be confirmed: ${ls_out}" >&2; return 2 ;;
    esac
    echo "     already landed: ${proof}; nothing to push, no PR opened"
    # A still-open PR (wrap merge's <branch>-squash fallback leaves the original open on
    # purpose) is reported, never closed as a side effect of deleting its branch.
    if [ "$open_count" -ge 1 ]; then
      echo "     PR #$(printf '%s' "$open_json" | jq -r '.[0].number' 2>/dev/null) still open for ${branch}: left untouched" >&2
      return 2
    fi
    # Nothing ran in the tree since the proof, so the only state the removal accepts is clean.
    _land_tidy "$repo" "$wt" "$branch" "$def" "$url" "$tip" "$origin_probe" ""
    return $?
  fi

  # A gitignored file under what the branch touches is invisible to the dirty check and to a
  # clean checkout alike: refuse before anything is pushed or opened.
  _land_ignored_guard "$wt" "$proof_base" "$branch" || return 1

  # A title-only body skips the repo's PR template (and any check that reads it), so a NEW
  # PR with no --body-file refuses before anything is pushed. An adopted PR keeps its body.
  if [ "$open_count" -eq 0 ] && [ -z "$body_file" ]; then
    local tpl; tpl="$(_pr_template "$wt")"
    if [ -n "$tpl" ]; then
      echo "     PR REFUSED: ${tpl} exists, so a title-only PR body is not allowed; fill it in and pass --body-file <file>" >&2
      return 2
    fi
  fi

  # Draft-only refusals, all before the push. The ship-gate call stands in for the PreToolUse
  # hook, which sees a literal `git push` in a Bash command and never sees this one.
  if [ "$draft" -eq 1 ]; then
    if [ "$open_count" -eq 1 ] && [ "$(printf '%s' "$open_json" | jq -r '.[0].isDraft // false' 2>/dev/null)" != "true" ]; then
      local nd_n; nd_n="$(printf '%s' "$open_json" | jq -r '.[0].number' 2>/dev/null)"
      echo "     DRAFT REFUSED: open PR #${nd_n} is not a draft; gh pr ready --undo ${nd_n} converts it, then rerun" >&2
      return 2
    fi
    if [ "$open_count" -eq 0 ] && [ -z "$body_file" ] && [ -z "$proof_body" ]; then
      echo "     DRAFT REFUSED: no proof-of-done file and no --body-file; a draft with a title-only body is not allowed" >&2
      return 2
    fi
    local gate gate_err gate_rc
    gate="${WRAP_LAND_SHIP_GATE:-$SELF_DIR/../../hooks/ship-gate.sh}"
    [ -z "${WRAP_LAND_SHIP_GATE:-}" ] || echo "     note: ship-gate path overridden by WRAP_LAND_SHIP_GATE (${gate})" >&2
    if [ ! -f "$gate" ]; then
      echo "     DRAFT REFUSED: ship-gate blocked the push" >&2
      echo "     ship-gate hook not found: ${gate}" >&2
      return 2
    fi
    # Stdout is dropped (a hook can print a JSON systemMessage there); stderr is the reason.
    gate_err="$(jq -n --arg cwd "$wt" --arg cmd "git push origin ${branch}" '{cwd: $cwd, tool_input: {command: $cmd}}' \
      | CLAUDE_PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-$(cd "$SELF_DIR/../.." && pwd)}" bash "$gate" 2>&1 >/dev/null)"; gate_rc=$?
    if [ "$gate_rc" -ne 0 ]; then
      echo "     DRAFT REFUSED: ship-gate blocked the push" >&2
      [ -z "$gate_err" ] || printf '%s\n' "$gate_err" >&2
      return 2
    fi
  fi

  git -C "$wt" push origin "$branch"; rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "     PUSH REFUSED: git push origin ${branch} exited ${rc}" >&2
    return "$rc"
  fi
  echo "     pushed ${branch} ($(_short "$tip"))"

  local created n pr_ref=""
  if [ "$open_count" -gt 1 ]; then
    echo "     PR REFUSED: ${open_count} open PRs for ${branch}" >&2; return 2
  elif [ "$open_count" -eq 1 ]; then
    n="$(printf '%s' "$open_json" | jq -r '.[0].number' 2>/dev/null)"
    case "$n" in
      ''|*[!0-9]*) echo "     PR REFUSED: open-PR lookup for ${branch} named no PR number" >&2; return 2 ;;
    esac
    local open_base; open_base="$(printf '%s' "$open_json" | jq -r '.[0].baseRefName' 2>/dev/null)"
    if [ "$open_base" != "$def" ]; then
      echo "     PR REFUSED: open PR #${n} targets ${open_base}, not ${def}" >&2; return 2
    fi
    # The same login read and case-insensitive compare _open_own_prs uses for `merge`.
    local me; me="$(gh api user --jq .login 2>/dev/null)"
    if [ -z "$me" ]; then
      echo "     PR REFUSED: open PR #${n}: operator login did not resolve" >&2; return 2
    fi
    local open_author; open_author="$(printf '%s' "$open_json" | jq -r '.[0].author.login // ""' 2>/dev/null)"
    if [ "$(printf '%s' "$open_author" | tr 'A-Z' 'a-z')" != "$(printf '%s' "$me" | tr 'A-Z' 'a-z')" ]; then
      echo "     PR REFUSED: open PR #${n} is authored by ${open_author}" >&2; return 2
    fi
    local open_draft; open_draft="$(printf '%s' "$open_json" | jq -r '.[0].isDraft // false' 2>/dev/null)"
    if [ "$open_draft" = "true" ] && [ "$draft" -eq 0 ]; then
      gh pr ready "$n" --repo "$url" >/dev/null 2>&1 || {
        echo "     PR REFUSED: open PR #${n} is a draft and gh pr ready failed" >&2; return 2; }
    fi
    if [ "$draft" -eq 1 ]; then echo "     adopted draft PR #${n}"; else echo "     adopted PR #${n}"; fi
    [ "$flags_given" -eq 1 ] && echo "     note: adopted PR #${n} keeps its own title and body" >&2
    pr_ref="$(printf '%s' "$open_json" | jq -r '.[0].url // ""' 2>/dev/null)"
    # An adopted PR keeps the body its author wrote. One that has none (empty, or only its
    # own title, which is what a title-only create leaves) takes the proof body.
    # A draft adopted with --body-file fills an empty body from that file instead.
    if [ -n "$proof_body" ] || { [ "$draft" -eq 1 ] && [ -n "$body_file" ]; }; then
      local open_body; open_body="$(printf '%s' "$open_json" | jq -r '.[0] | if ((.body // "") == "" or .body == .title) then "none" else "own" end' 2>/dev/null)"
      if [ "$open_body" = "none" ]; then
        local fill_from="the proof of done" fill=(--body "$proof_body")
        [ -z "$body_file" ] || { fill_from="$body_file"; fill=(--body-file "$body_file"); }
        if gh pr edit "$n" --repo "$url" "${fill[@]}" >/dev/null 2>&1; then
          echo "     PR #${n} body set from ${fill_from}"
        else
          echo "     note: PR #${n} body could not be set from the proof of done" >&2
        fi
      fi
    fi
  else
    # `--head`, never `--base`: a base the caller names is the way a PR ends up targeting
    # another feature branch. With --repo, gh targets the repository's own default branch.
    local -a draft_arg=(); [ "$draft" -eq 0 ] || draft_arg=(--draft)
    if [ -n "$body_file" ]; then
      created="$(gh pr create --repo "$url" --head "$branch" ${draft_arg[@]+"${draft_arg[@]}"} --title "$title" --body-file "$body_file" 2>&1)"; rc=$?
    else
      created="$(gh pr create --repo "$url" --head "$branch" ${draft_arg[@]+"${draft_arg[@]}"} --title "$title" --body "${proof_body:-$title}" 2>&1)"; rc=$?
    fi
    if [ "$rc" -ne 0 ]; then
      echo "     PR REFUSED: gh pr create exited ${rc}: ${created}" >&2; return 2
    fi
    pr_ref="$(printf '%s\n' "$created" | tail -1)"; n="${pr_ref##*/}"
    case "$n" in
      ''|*[!0-9]*) echo "     PR REFUSED: gh pr create named no PR number: ${created}" >&2; return 2 ;;
    esac
    if [ "$draft" -eq 1 ]; then
      # One read confirms the flag took: a ready PR left behind could be merged by a later plain land.
      local made_draft; made_draft="$(gh pr view "$n" --repo "$url" --json isDraft 2>/dev/null | jq -r '.isDraft // false' 2>/dev/null)"
      if [ "$made_draft" != "true" ]; then
        echo "     DRAFT REFUSED: PR #${n} was created ready; gh pr ready --undo ${n} converts it (the PR stays open)" >&2
        return 2
      fi
      echo "     opened draft PR #${n}"
    else
      echo "     opened PR #${n}"
    fi
  fi

  # The draft exit: the PR is open and still a draft, so nothing below (checks, merge, tree
  # verify, Ship record, tidy) may run. The worktree stays for the operator's review.
  if [ "$draft" -eq 1 ]; then
    echo "     draft PR: ${pr_ref:-#${n}}"
    echo "     worktree kept: ${wt}"
    [ -z "$proof_base" ] || _land_proof_block "$wt" "$proof_base" "${pr_ref:-#${n}}"
    return 0
  fi

  # Under `--with-ci`/`KIT_WRAP_CI_ON_MERGE=1` a label-gated repo runs no checks until the
  # PR carries `ci`, so the label goes on before the merge and the runs it starts get a
  # bounded wait. With the gate off (the default), or on a repo without the label, the
  # merge runs as it always did; under the gate, a label that could not be set refuses
  # rather than merging untested.
  if _ci_on_merge; then
    _ci_label_sync "$url" "$n"; rc=$?
    case "$rc" in
      0) _ci_checks_wait "$url" "$n" ;;
      1) ;;
      *) echo "     MERGE FAILED #${n}: the ci label could not be set" >&2; return 2 ;;
    esac
  fi

  _land_pr_checks_gate "$wt" "$url" "$n" || return 2

  _gh_merge_retry "$n" "$url" "$tip"; rc=$?
  if [ "$rc" -ne 0 ]; then
    # A refusal worth answering is CONFLICTING and nothing else: the branch is already
    # pushed, so one merge of origin/<def> into it (never a rebase) is the only move that
    # keeps the published history. Any other verdict keeps today's exit.
    local mdetail mhead m mgen mrc proll pnum pwaited failed_checks
    mdetail="$(_pr_detail_at_head "$url" "$n" "$tip")"
    mhead="$(printf '%s' "$mdetail" | jq -r '.headRefOid // ""' 2>/dev/null)"
    if [ -z "$mdetail" ] || [ -z "$mhead" ]; then
      echo "     MERGE FAILED #${n}: exit ${rc}; the PR state is unreadable, nothing merged" >&2
      return 2
    fi
    if [ "$mhead" != "$tip" ]; then
      echo "     MERGE FAILED #${n}: GitHub still shows head $(_short "$mhead"), not the pushed $(_short "$tip")" >&2
      return 2
    fi
    m="$(printf '%s' "$mdetail" | jq -r '.mergeable // "UNKNOWN"' 2>/dev/null)"
    if [ "$m" != "CONFLICTING" ]; then
      echo "     MERGE FAILED #${n}: exit ${rc}" >&2; return 2
    fi
    echo "     #${n} is CONFLICTING: merging origin/${def} into ${branch}"
    mgen=""; [ -f "$wt/$_RB_GENERATOR" ] && mgen="$wt/$_RB_GENERATOR"
    if [ -n "$verify" ]; then
      _merge_verify_push "$wt" "$branch" "$def" "$tip" "$mgen" "$verify"
    else
      _merge_verify_push "$wt" "$branch" "$def" "$tip" "$mgen"
    fi
    mrc=$?
    case "$mrc" in
      0) ;;
      4) echo "     ${branch} already contains origin/${def}; GitHub's conflict is the union-blind case, run wrap merge --apply --pr ${n}" >&2
         return 2 ;;
      130) return 130 ;;
      *) echo "     PR #${n} left open" >&2; return 2 ;;
    esac

    # From here on the merge commit is on origin whatever happens next, so every exit names
    # it: a rerun that cannot see that sha would merge the wrong head.
    echo "     waiting for GitHub to see $(_short "$MERGED_OID")"
    mdetail="$(_pr_detail_settled "$url" "$n" "$MERGED_OID" "$tip")"
    mhead="$(printf '%s' "$mdetail" | jq -r '.headRefOid // ""' 2>/dev/null)"
    m="$(printf '%s' "$mdetail" | jq -r '.mergeable // "UNKNOWN"' 2>/dev/null)"
    if [ -z "$mdetail" ] || [ -z "$mhead" ]; then
      echo "     #${n} is unreadable after the push; the merge commit $(_short "$MERGED_OID") is on origin" >&2
      return 2
    fi
    if [ "$mhead" = "$tip" ]; then
      echo "     GitHub has not caught up with $(_short "$MERGED_OID"); run wrap merge --apply --pr ${n}; the merge commit $(_short "$MERGED_OID") is on origin" >&2
      return 2
    fi
    if [ "$mhead" != "$MERGED_OID" ]; then
      echo "     PR #${n} head is $(_short "$mhead"), another writer pushed; left open; the merge commit $(_short "$MERGED_OID") is on origin" >&2
      return 2
    fi
    if [ "$m" = "CONFLICTING" ]; then
      echo "     #${n} is still CONFLICTING; run wrap merge --apply --pr ${n}; the merge commit $(_short "$MERGED_OID") is on origin" >&2
      return 2
    fi
    tip="$MERGED_OID"

    if _ci_on_merge; then
      _ci_label_sync "$url" "$n"; rc=$?
      case "$rc" in
        0) _ci_checks_wait "$url" "$n" ;;
        1) ;;
        *) echo "     MERGE FAILED #${n}: the ci label could not be set; the merge commit $(_short "$tip") is on origin" >&2
           return 2 ;;
      esac
      proll="$(gh pr view "$n" --repo "$url" --json statusCheckRollup 2>/dev/null)"; rc=$?
    else
      # The pending-only wait holds no grace: a push that starts no checks pays nothing.
      # An unreadable read ends it at once; the single judgment below reads the last
      # answer either way.
      pwaited=0
      while :; do
        proll="$(gh pr view "$n" --repo "$url" --json statusCheckRollup 2>/dev/null)"; rc=$?
        [ "$rc" -eq 0 ] && [ -n "$proll" ] || break
        pnum="$(printf '%s' "$proll" | jq -r "${CI_JQ_DEFS} ([.statusCheckRollup // [] | .[] | select(pending)] | length)" 2>/dev/null)"
        case "$pnum" in ''|*[!0-9]*) break ;; esac
        [ "$pnum" -eq 0 ] && break
        [ "$pwaited" -lt "$KIT_WRAP_CARRY_CHECKS_SECS" ] || break
        sleep 10; pwaited=$(( pwaited + 10 ))
      done
    fi
    # The merge commit is already on origin, so what the rollup cannot answer is judged
    # against a state that cannot be taken back: an unreadable read, or checks still
    # pending when the bound ran out, stop the land naming the commit the same way a red
    # check does. A readable rollup with nothing pending -- the empty one of a repo that
    # registered no checks included -- keeps the straight path.
    if [ "$rc" -ne 0 ] || ! printf '%s' "$proll" | jq -e . >/dev/null 2>&1; then
      echo "     checks unreadable on the merged head $(_short "$tip"); the merge commit is on origin" >&2
      return 2
    fi
    pnum="$(printf '%s' "$proll" | jq -r "${CI_JQ_DEFS} ([.statusCheckRollup // [] | .[] | select(pending)] | length)" 2>/dev/null)"
    if [ "$pnum" != "0" ]; then
      echo "     checks still pending on the merged head $(_short "$tip"); the merge commit is on origin" >&2
      return 2
    fi
    # A red check on the merged head stops the land before the second merge: a clean
    # textual merge that broke the build must never land. Latest run per name wins, the
    # same dedupe _pr_gate applies.
    failed_checks="$(_rollup_failed_checks "$proll")"
    if [ -n "$failed_checks" ]; then
      echo "     checks failed on the merged head $(_short "$tip"): ${failed_checks}; the merge commit is on origin" >&2
      return 2
    fi
    _gh_merge_retry "$n" "$url" "$tip"; rc=$?
    if [ "$rc" -ne 0 ]; then
      echo "     MERGE FAILED #${n}: exit ${rc} after the merge cycle; once its checks pass, run wrap merge --apply --pr ${n}; the merge commit $(_short "$tip") is on origin" >&2
      return 2
    fi
  fi

  local after state sha
  after="$(gh pr view "$n" --repo "$url" --json state,mergeCommit 2>/dev/null)"
  state="$(printf '%s' "$after" | jq -r '.state // ""' 2>/dev/null)"
  sha="$(printf '%s' "$after" | jq -r '.mergeCommit.oid // ""' 2>/dev/null)"
  if [ "$state" != "MERGED" ]; then
    echo "     MERGE FAILED #${n}: state is '${state:-unknown}', not MERGED" >&2; return 2
  fi
  local tv; tv="$(_tree_verify "$wt" "$def" "$tip" "$sha")"
  case "$tv" in
    OK) echo "     merged #${n} (${sha}): tree verified" ;;
    MISMATCH*)
      echo "     merged #${n} (${sha}): TREE MISMATCH, ${tv#MISMATCH } paths differ; ${def} does not hold the PR head" >&2
      return 3 ;;
    *)
      echo "     merged #${n} (${sha}): tree ${tv}" >&2
      return 3 ;;
  esac

  # Ship-gate record: `/kit:ship` records `| GATE | ship | ran | shipping pr=#<n>`
  # on its own path (commands/ship.md Step 8); `land` never did, so a spec cycle shipped
  # through `land` instead never trips /kit:wrap step 8's retro-trigger grep. Reuse the
  # existing `rid` verb (cwd'd into the worktree, still on the landed branch -- removal is
  # several steps below) rather than reimplementing its slug rule, and record only when the
  # rid already started a run (a `show` hit), so a plain hand-made land with no spec cycle
  # behind it stays silent. The reason carries `via=land` so this line is distinguishable
  # from one hooks/ship-gate.sh actually gated (it only fires on a literal push/PR-create);
  # /kit:wrap step 8's `shipping pr=#<n>([^0-9]|$)` grep still matches it (the next char is
  # a space). A rid whose ledger already carries a `ship` gate line is never recorded a
  # second time: the same PR number is an idempotent re-land (e.g. /kit:ship already wrote
  # it), a different PR number means this rid's slug is shared by an unrelated branch (a
  # reused `type/` prefix, same stripped slug) and overwriting it would misattribute the
  # line. A failed derive or record never fails the land: one line instead, naming the
  # command to run by hand.
  local land_rid; land_rid="$(cd "$wt" && bash "$GATE_LEDGER_SH" rid 2>/dev/null)" || land_rid=""
  if [ -n "$land_rid" ]; then
    local land_ledger
    if land_ledger="$(bash "$GATE_LEDGER_SH" show "$land_rid" 2>/dev/null)"; then
      local prior_pr
      prior_pr="$(printf '%s\n' "$land_ledger" | grep -i '| GATE | ship |' | grep -oE 'pr=#[0-9]+' | tail -1)"
      if [ "$prior_pr" = "pr=#${n}" ]; then
        echo "     ship gate for ${land_rid} already names pr=#${n}; skipping (already recorded)"
      elif [ -n "$prior_pr" ]; then
        echo "     ship gate for ${land_rid} already names ${prior_pr}, not pr=#${n}; skipping (reused slug, different run)"
      else
        local record_err
        if record_err="$(bash "$GATE_LEDGER_SH" record "$land_rid" Ship ran "shipping pr=#${n} via=land" 2>&1 >/dev/null)"; then
          echo "     recorded ship gate for ${land_rid} (pr=#${n})"
        else
          echo "     ship-gate record FAILED for ${land_rid} (pr=#${n}): ${record_err}; record it by hand: bash ${GATE_LEDGER_SH} record ${land_rid} Ship ran \"shipping pr=#${n} via=land\"" >&2
        fi
      fi
    fi
  fi

  # The proof block is read before the tidy removes the worktree and printed after it, so it
  # is the last thing the operator (and the agent's final report) sees.
  local proof_block=""
  [ -z "$proof_base" ] || proof_block="$(_land_proof_block "$wt" "$proof_base" "${pr_ref:-#${n}}")"
  _land_tidy "$repo" "$wt" "$branch" "$def" "$url" "$tip" "" "$base_ignored"; rc=$?
  [ -z "$proof_block" ] || printf '%s\n' "$proof_block"
  return "$rc"
}

# _land_tidy <repo> <wt> <branch> <def> <url> <tip> [<origin_probe> [<allowed>]] -- the tail both land
# paths share once the branch is proven on the default branch: retire the origin branch,
# fast-forward the main checkout, remove the worktree, delete the local branch. <origin_probe>
# is `absent` or `present` when the caller already read origin's copy of the branch; without
# one this reads it itself; only `ls-remote --exit-code` exit 2 counts as gone, any other
# failure falls through to the delete attempt and its own FAILED line. <allowed> is the
# caller's expected tree state: the `status --porcelain` lines the tree may show at removal.
# Empty means clean. The caller takes it before the work that could write, never here, so a
# write made during that work is a difference and not a baseline.
_land_tidy() {
  local repo="$1" wt="$2" branch="$3" def="$4" url="$5" tip="$6" probe="${7:-}" allowed="${8:-}"
  # Mirrors _apply_origin_branches: leased to the tip land itself pushed, skipped when an
  # open PR still bases off this branch (deleting it would close that PR), and never fails
  # land, since the merge is already verified.
  if [ "$(kit_config_get_root wrap.delete_merged_remote_branches true)" != "true" ]; then
    echo "     ${branch} left on origin (wrap.delete_merged_remote_branches=false)"
  else
    if [ -z "$probe" ]; then
      git -C "$wt" ls-remote --exit-code origin "refs/heads/${branch}" >/dev/null 2>&1
      [ "$?" -eq 2 ] && probe=absent
    fi
    local base_open
    if [ "$probe" = "absent" ]; then
      echo "     ${branch} already gone from origin"
      base_open=skip
    else
      base_open="$(gh pr list --repo "$url" --state open --json baseRefName 2>/dev/null \
        | jq -r --arg b "$branch" '[.[] | select(.baseRefName == $b)] | length' 2>/dev/null)"
    fi
    case "$base_open" in
      skip) ;;
      0)
        if git -C "$wt" push -q origin "--force-with-lease=refs/heads/${branch}:${tip}" ":refs/heads/${branch}" 2>/dev/null; then
          echo "     deleted ${branch} on origin"
        else
          echo "     FAILED delete ${branch} on origin (protected, no permission, or pushed since land read it)"
        fi ;;
      ''|*[!0-9]*) echo "     FAILED delete ${branch} on origin (open-PR lookup failed)" ;;
      *) echo "     ${branch} left on origin: an open PR bases off it" ;;
    esac
  fi

  # The fast-forward is advisory: a checkout this call does not own may be dirty or on
  # another branch, and neither is a reason to strand a merged worktree. A dirty file the
  # repo declares merge=union is carried across (_land_ff_pull); any other dirty
  # file is never stashed past and never reset; the refusal is reported and the tidy continues.
  # Under --no-pull (a step 0 stop) the main checkout belongs to a live session, so the
  # fast-forward is skipped with the same line `apply --no-pull` prints.
  local blocked=0 cur
  cur="$(git -C "$repo" branch --show-current 2>/dev/null)"
  if [ "$NO_PULL" = 1 ]; then
    echo "     SKIP pull: --no-pull"
  elif [ "$cur" != "$def" ]; then
    echo "     PULL BLOCKED: ${repo} is on '${cur:-<detached>}', not ${def}"
    blocked=1
  elif _land_ff_pull "$repo"; then
    echo "     pulled ${repo}: $(git -C "$repo" log --oneline -1 2>/dev/null)"
  else
    echo "     PULL BLOCKED: pull --ff-only refused in ${repo}, nothing was stashed or reset"
    blocked=1
  fi

  # The pull and the origin delete above can cost network round trips, and `-f -f` below
  # discards a dirty tree and `-D` a newer commit, so both are re-read right before the
  # removal. A mismatch skips only the removal; what already ran stands.
  # Any status line outside <allowed> refuses and names its path; an unreadable status does too.
  local st_now st_rc line extra="" detail=""
  st_now="$(git -C "$wt" status --porcelain 2>/dev/null)"; st_rc=$?
  [ "$st_rc" -eq 0 ] || detail=" (status unreadable)"
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    case $'\n'"$allowed"$'\n' in *$'\n'"$line"$'\n'*) continue ;; esac
    extra="${line#???}"; detail=" (${extra})"; break
  done <<< "$st_now"
  if [ -n "$detail" ] || [ "$(git -C "$wt" rev-parse HEAD 2>/dev/null)" != "$tip" ]; then
    echo "     ${branch} changed since it was checked${detail}; worktree and branch left in place" >&2
    return 2
  fi

  # A live process holding the worktree (its cwd or an open file) would keep writing into a
  # deleted path, so the merge stands and the worktree and branch stay.
  if _wt_busy "$wt"; then
    echo "     ${BUSY_MSG}"
    echo "     ${branch} is merged; worktree ${wt} and ${branch} stay until the holder exits"
    [ "$blocked" = 0 ] || return 2
    return 0
  fi

  # `-f -f` overrides the lock the Agent tool puts on every worktree it creates; the merge
  # proof above is what earns the removal. The removal counts only once the path is gone.
  git -C "$repo" worktree remove -f -f "$wt" >/dev/null 2>&1
  if ! _wt_cleared "$repo" "$wt"; then
    echo "     FAILED remove worktree ${wt}: it survived, so ${branch} stays" >&2
    return 2
  fi
  echo "     removed worktree ${wt}"
  if git -C "$repo" branch -D "$branch" >/dev/null 2>&1; then
    echo "     deleted ${branch}"
  else
    echo "     FAILED delete ${branch}" >&2
    return 2
  fi

  [ "$blocked" = 0 ] || return 2
  return 0
}

