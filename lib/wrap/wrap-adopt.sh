# wrap-adopt.sh -- the adopt verb: one call that adopts a repo into the kit contract
# and lands the adoption; sourced by lib/wrap/wrap.sh.
#
# `wrap.sh adopt [--apply] [--body-file F] <repo> [<repo>...]` -- without --apply a
# dry run: every preflight read (R3) and `adopt.sh --dry-run` run, the row prints
# `would adopt` or the refusal, and nothing writes (no fetch, no worktree, no
# branch, no ledger line). --apply is operator-only by policy: an agent runs the dry
# run and hands the operator the --apply command line; nothing in the verb can tell
# who typed it.
#
# Per repo the report is one `== <repo>` block: adopt's own output indented four
# spaces, then `  result: <#n or -> <row>` printed as the repo finishes.

# The branch every adoption lands on, and the file set it may touch. A path matches
# ADOPT_PATHS when it equals a listed file or sits under the listed directory; R3c
# and R3k read it as a pathspec list and the apply-path guard matches the same list.
ADOPT_BRANCH="chore/kit-adopt"
ADOPT_PATHS="AGENTS.md CLAUDE.md WORKFLOW.md .kit.toml docs/verification/README.md .claude/settings.json .claude/output-styles/"
ADOPT_COMMIT_SUBJECT="chore: adopt the dwarves-kit operate-contract"
ADOPT_COMMIT_BODY="AGENTS.md pointer, CLAUDE.md loader, WORKFLOW pointer, proof marker, starter .kit.toml, kit hook wiring."
OVERRIDE_REASON="written by wrap adopt --apply: adoption scaffold only, every path in ADOPT_PATHS (R6); .claude/settings.json changes limited to kit hook commands and outputStyle (R6a); no other file changed"
# Passed to jq as --arg re and applied with test(): \A and \z reject an embedded
# newline, which ^ and $ would let past. Matches the two command shapes the kit's
# settings.json ships (bare hook, or behind anchor-root.sh), each with optional
# --flag arguments. $HOME is literal text in the file, never expanded.
ADOPT_HOOK_RE='\Abash \$HOME/\.claude/dwarves-kit/hooks/(anchor-root\.sh \$HOME/\.claude/dwarves-kit/hooks/)?[A-Za-z0-9_-]+\.sh( --[a-z][a-z-]*)*\z'

# The file writer preflight always runs. WRAP_ADOPT_SH replaces it for the apply
# path's R5 call alone, and only under WRAP_ADOPT_TEST=1 (an unflagged inherited
# value must never swap the writer that runs right before an override and a merge).
ADOPT_SH="$LIB_ROOT/adopt.sh"

# The apply path's per-repo scratch (start's stderr, the captured land log R8
# parses). cmd_adopt creates it once and the verb's EXIT trap removes it.
ADOPT_TMP=""
ADOPT_ROW=""; ADOPT_PR="-"; ADOPT_STOP=0
# The batch (R10): repos in argument order, each one's summary name, PR column
# and row, the running index, and the worktree once cmd_start printed one. The
# INT/TERM trap reads them, so they are globals.
ADOPT_N=0; ADOPT_I=1; ADOPT_WT=""
ADOPT_REPOS=(); ADOPT_NAMES=(); ADOPT_PRS=(); ADOPT_ROWS=()

# _adopt_blob <repo> <revspec> -- a blob's text (empty when absent), never an error.
_adopt_blob() { git -C "$1" show "$2" 2>/dev/null; }

# _adopt_style_of <repo> <rev-prefix> -- the outputStyle in <prefix>'s
# .claude/settings.json; <rev-prefix> is `:` for the index, HEAD, or a commit.
_adopt_style_of() {
  local spec
  case "$2" in
    :*) spec="$2.claude/settings.json" ;;
    *)  spec="$2:.claude/settings.json" ;;
  esac
  _adopt_blob "$1" "$spec" | jq -r '.outputStyle // ""' 2>/dev/null
}

# _adopt_path_ok <path> <staged-style> -- 0 when <path> is inside ADOPT_PATHS:
# the six fixed files, or .claude/output-styles/<s>.md for the style the staged
# settings actually name (R6 narrows the directory to that one file).
_adopt_path_ok() {
  case "$1" in
    AGENTS.md|CLAUDE.md|WORKFLOW.md|.kit.toml|docs/verification/README.md|.claude/settings.json) return 0 ;;
    .claude/output-styles/*)
      [ -n "$2" ] && [ "$1" = ".claude/output-styles/$2.md" ] ;;
    *) return 1 ;;
  esac
}

# _adopt_paths_miss <staged-style> -- reads a -z path list on stdin and prints
# the first path outside ADOPT_PATHS; prints nothing when the list is clean.
_adopt_paths_miss() {
  local p
  while IFS= read -r -d '' p; do
    _adopt_path_ok "$p" "$1" || { printf '%s\n' "$p"; return 0; }
  done
}

# _adopt_settings_diff <staged-json> <base-json> -- R6a, all matching inside jq
# test() so an embedded newline stays inside one command string. Exits 0 silent
# when staged differs from base only by kit-hook adds and outputStyle; exits 1
# printing the miss detail -- `key <name>` for a top-level key, `<event>
# <matcher> #<index>` for a staged non-kit hook entry -- never the command text.
_adopt_settings_diff() {
  local staged="$1" base="$2" miss
  [ -n "$staged" ] || staged="{}"
  [ -n "$base" ] || base="{}"
  printf '%s' "$staged" | jq -e . >/dev/null 2>&1 || { echo "staged blob unreadable"; return 1; }
  printf '%s' "$base" | jq -e . >/dev/null 2>&1 || { echo "base blob unreadable"; return 1; }

  # A staged outputStyle keeps the bare-name shape adopt.sh step 6b accepts.
  if ! printf '%s' "$staged" | jq -e '
      (.outputStyle // null) as $s
      | ($s == null) or (($s | type) == "string"
          and ($s | test("\\A[A-Za-z0-9_.-]+\\z")) and ($s | contains("..") | not))' >/dev/null 2>&1; then
    echo "key outputStyle"; return 1
  fi

  # A non-hook top-level key is a refusal on its own name. A jq failure anywhere
  # below is a miss too: a guard that reads nothing must never pass.
  if ! miss="$(jq -nr --argjson s "$staged" --argjson b "$base" '
    def ok: keys_unsorted - ["hooks", "outputStyle"];
    ($s | ok) as $sk | ($b | ok) as $bk
    | ([ $sk[] | select(. as $k | (($bk | index($k)) == null) or ($b[$k] != $s[$k])) ]
       + [ $bk[] | select(. as $k | ($sk | index($k)) == null) ])
    | .[0] // empty')"; then
    echo "key diff unreadable"; return 1
  fi
  [ -z "$miss" ] || { echo "key ${miss}"; return 1; }

  # Every staged hook entry absent from the base must be a kit entry: a command
  # type, only the keys a settings hook may carry, command matching ADOPT_HOOK_RE.
  if ! miss="$(jq -nr --argjson s "$staged" --argjson b "$base" --arg re "$ADOPT_HOOK_RE" '
    def hooksobj: ((.hooks // {}) | if type == "object" then . else {} end);
    def iskit:
      (type == "object")
      and ((.type // "") == "command")
      and (((keys - ["type", "command", "timeout", "async"]) | length) == 0)
      and (((.command // "") | tostring) | test($re));
    [$b | hooksobj | to_entries[] | .value[]? | .hooks[]?] as $bset
    | [ $s | hooksobj | to_entries[] | .key as $ev
        | .value[]? | . as $g
        | (($g.hooks // []) | if type == "array" then . else [] end | to_entries[]) | .key as $i | .value as $e
        | select((any($bset[]; . == $e)) | not)
        | select(($e | iskit) | not)
        | "\($ev) \((if ($g | type) == "object" then ($g.matcher // "-") else "-" end)) #\($i)" ]
    | .[0] // empty')"; then
    echo "entry diff unreadable"; return 1
  fi
  [ -z "$miss" ] || { echo "$miss"; return 1; }

  # What remains after the kit's own entries are stripped must be unchanged: on
  # the staged side the kit entries adopt just wired, on the base side every
  # entry whose command names dwarves-kit/hooks/ (what adopt strips before its
  # merge, stale kit hooks included). Emptied groups, events and the hooks
  # object itself drop out on both sides, and arrays sort by their own text.
  if ! miss="$(jq -nr --argjson s "$staged" --argjson b "$base" --arg re "$ADOPT_HOOK_RE" '
    def hooksobj: ((.hooks // {}) | if type == "object" then . else {} end);
    def iskit:
      (type == "object")
      and ((.type // "") == "command")
      and (((keys - ["type", "command", "timeout", "async"]) | length) == 0)
      and (((.command // "") | tostring) | test($re));
    def kitc: ((.command // "") | tostring) | contains("dwarves-kit/hooks/");
    def norm(drop):
      hooksobj
      | to_entries
      | map(.value |= ( map(.hooks = ((.hooks // []) | map(select(drop | not)) | sort | unique))
                        | map(select((.hooks | length) > 0)) | sort ))
      | map(select((.value | length) > 0))
      | from_entries;
    if (($s | norm(iskit)) == ($b | norm(kitc))) then empty else "hooks" end')"; then
    echo "hook diff unreadable"; return 1
  fi
  [ -z "$miss" ] || { echo "key hooks"; return 1; }
  return 0
}

# _adopt_commit_guard <repo> <tip-ref> <base-ref> -- R6's path check and R6a on a
# COMMITTED diff (R6b's post-commit recheck, and R3f's leftover judgment). Prints
# the first miss (a path, or an R6a detail) and exits 1; exits 0 silent.
_adopt_commit_guard() {
  local repo="$1" tip="$2" base="$3" style miss sd
  style="$(_adopt_style_of "$repo" "$tip")"
  miss="$(git -C "$repo" diff --name-only --no-renames -z "$base" "$tip" | _adopt_paths_miss "$style")"
  [ -z "$miss" ] || { printf '%s\n' "$miss"; return 1; }
  [ -n "$(git -C "$repo" diff --name-only --no-renames "$base" "$tip" -- .claude/settings.json)" ] \
    || return 0
  if ! sd="$(_adopt_settings_diff "$(_adopt_blob "$repo" "${tip}:.claude/settings.json")" \
                                  "$(_adopt_blob "$repo" "${base}:.claude/settings.json")")"; then
    printf '%s\n' "$sd"; return 1
  fi
  return 0
}

PF_STATUS=""
PF_REASONS=""
PF_NOTE=""
PF_DEF=""
ADOPT_DRY=""
ADOPT_STYLE=""
_pf_add() { PF_REASONS="${PF_REASONS:+$PF_REASONS; }$1"; }

# _adopt_preflight <repo> <body-file> -- every read-only check R3 names, in the
# picture's order: --check, main checkout, collision status, sequencer, unmerged,
# the chore/kit-adopt shapes, on-default, PR template, adopt --dry-run, ignored
# paths. R3a short-circuits to `skip`; every other reason found joins the row with
# `; `. Sets PF_STATUS to skip|refused|ok, PF_REASONS to the joined list, ADOPT_DRY
# to the adopt --dry-run stdout, ADOPT_STYLE to any reported outputStyle name, and
# PF_NOTE to the stale-read note when HEAD disagrees with the tracking ref. Never
# writes.
_adopt_preflight() {
  local repo="$1" bodyfile="$2"
  PF_STATUS="ok"; PF_REASONS=""; PF_NOTE=""; ADOPT_DRY=""; ADOPT_STYLE=""
  local gd cgd main_co=1 def="" cur up tpl style="" drc drf
  local line s sp p paths wt tip otip url="" json ghrc nums ahead=""
  local ono=0 wtp=0 rebase_seen=0 lmb lmiss
  PF_DEF=""

  # R3a short-circuits: an adopted repo needs no other read.
  if "$ADOPT_SH" --check "$repo" >/dev/null 2>&1; then
    PF_STATUS="skip"; return 0
  fi

  def="$(_default_branch "$repo" 2>/dev/null)"
  [ -n "$def" ] || _pf_add "no default branch resolved"

  # R3b: a main checkout's git dir IS its common dir; a linked worktree's differs.
  gd="$(git -C "$repo" rev-parse --path-format=absolute --git-dir 2>/dev/null)"
  cgd="$(git -C "$repo" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
  if [ -z "$gd" ] || [ -z "$cgd" ] || [ "$gd" != "$cgd" ]; then
    main_co=0; _pf_add "not a main checkout"
  fi

  # R3c: any status line under an ADOPT_PATHS pathspec blocks the post-land pull.
  while IFS= read -r line; do
    [ -n "$line" ] && _pf_add "$line in the main checkout would block the post-land pull"
  done < <(git -C "$repo" status --porcelain --untracked-files=all --no-renames -- $ADOPT_PATHS 2>/dev/null)

  # R3d: a sequencer op in progress.
  for s in MERGE_HEAD rebase-merge rebase-apply CHERRY_PICK_HEAD REVERT_HEAD; do
    sp="$(git -C "$repo" rev-parse --path-format=absolute --git-path "$s" 2>/dev/null)" || continue
    [ -e "$sp" ] || continue
    case "$s" in
      MERGE_HEAD)       _pf_add "mid-merge" ;;
      rebase-merge|rebase-apply)
        [ "$rebase_seen" = 0 ] && { rebase_seen=1; _pf_add "mid-rebase"; } ;;
      CHERRY_PICK_HEAD) _pf_add "mid-cherry-pick" ;;
      REVERT_HEAD)      _pf_add "mid-revert" ;;
    esac
  done

  # R3e: unmerged index entries stand on their own, sequencer or not.
  paths="$(git -C "$repo" ls-files -u 2>/dev/null | sed 's/.*\t//' | sort -u | tr '\n' ' ')"
  paths="${paths% }"
  [ -n "$paths" ] && _pf_add "unmerged paths: $paths"

  # R3f: a leftover chore/kit-adopt in any of its three shapes.
  wt="$repo/.claude/worktrees/kit-adopt"
  _ref_exists "$repo" "refs/remotes/origin/${ADOPT_BRANCH}" && ono=1
  if [ "$ono" = 0 ]; then
    url="$(_origin_url "$repo")"
    if [ -n "$url" ]; then
      git -C "$repo" ls-remote --exit-code --heads origin "$ADOPT_BRANCH" >/dev/null 2>&1
      # Exit 2 is the only "absent" --exit-code gives; anything else is a failed read.
      case $? in
        0) ono=1 ;;
        2) ;;
        *) _pf_add "origin unreachable" ;;
      esac
    fi
  fi
  _ref_exists "$repo" "refs/heads/${ADOPT_BRANCH}" && _pf_add "chore/kit-adopt exists locally"
  [ "$ono" = 1 ] && _pf_add "chore/kit-adopt exists on origin"
  [ -e "$wt" ] && { wtp=1; _pf_add "chore/kit-adopt worktree path exists"; }

  # The merged-PR read runs only when the leftover is live enough to resume: the
  # worktree on the branch, and the branch ahead of the tracking tip (no fetch). A
  # land exit 3 leaves exactly this shape behind a merged PR, which is why `resume:`
  # is never printed until the PR state is read.
  if [ "$wtp" = 1 ] && [ "$(git -C "$wt" branch --show-current 2>/dev/null)" = "$ADOPT_BRANCH" ] \
     && [ -n "$def" ] && _ref_exists "$repo" "refs/remotes/origin/$def"; then
    ahead="$(git -C "$repo" rev-list --count "refs/remotes/origin/$def..refs/heads/$ADOPT_BRANCH" 2>/dev/null)"
  fi
  if [ -n "$ahead" ] && [ "$ahead" != "0" ]; then
    json="$(gh pr list --repo "$url" --head "$ADOPT_BRANCH" --state merged \
            --json number,headRefOid,baseRefName,mergedAt 2>/dev/null)"; ghrc=$?
    if [ "$ghrc" -ne 0 ] || ! printf '%s' "$json" | jq -e 'type == "array"' >/dev/null 2>&1; then
      _pf_add "PR state unreadable; read $wt"
    else
      tip="$(git -C "$wt" rev-parse HEAD 2>/dev/null)"
      # The CONFLICTING cycle pushes a merge commit, so the merged PR's head can be
      # origin's tracking tip rather than the worktree's; both count as a match.
      otip="$(git -C "$repo" rev-parse -q --verify "refs/remotes/origin/$ADOPT_BRANCH" 2>/dev/null)"
      nums="$(printf '%s' "$json" | jq -r --arg def "$def" --arg a "$tip" --arg b "$otip" '
        [.[] | select(.mergedAt != null and .baseRefName == $def
                      and (.headRefOid == $a or .headRefOid == $b)) | .number] | .[]')"
      if [ -n "$nums" ]; then
        _pf_add "merged #$(printf '%s' "$nums" | tr '\n' ' ' | sed 's/ $//; s/ / #/g'); read $wt"
      else
        # DEC-V: R6 and R6a re-run on the leftover's committed diff before the
        # `resume:` prints; a hand `wrap land` merges whatever the branch holds
        # with no gate in the way (G4), so a miss reads `read <wt>` instead.
        lmb="$(git -C "$repo" merge-base "refs/remotes/origin/$def" "refs/heads/$ADOPT_BRANCH" 2>/dev/null)"
        lmiss="merge-base unresolved"
        [ -n "$lmb" ] && lmiss="$(_adopt_commit_guard "$repo" "refs/heads/$ADOPT_BRANCH" "$lmb")"
        if [ -n "$lmiss" ]; then
          _pf_add "read $wt"
        else
          _pf_add "resume: wrap land $wt${bodyfile:+ --body-file $bodyfile}"
        fi
      fi
    fi
  fi

  # R3g: the pull lands in the main checkout, so it must sit on the default branch.
  # Skipped when R3b fired: "main checkout is on ..." presumes one exists.
  if [ "$main_co" = 1 ] && [ -n "$def" ]; then
    cur="$(git -C "$repo" branch --show-current 2>/dev/null)"
    if [ "$cur" != "$def" ]; then
      _pf_add "main checkout is on ${cur:-<detached>}, not $def"
    else
      up="$(git -C "$repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
      [ -n "$up" ] && [ "$up" != "origin/$def" ] \
        && _pf_add "main checkout tracks $up, not origin/$def"
    fi
  fi

  # R3h: land refuses a title-only body when the repo carries a PR template.
  tpl="$(_pr_template "$repo" 2>/dev/null)"
  [ -n "$tpl" ] && [ -z "$bodyfile" ] && _pf_add "$tpl exists; pass --body-file"

  # R3i: adopt's own refusal (the kit's own tree, single-source both-files, a
  # missing template). The stdout copy also feeds R3k's style detection.
  drf="$(mktemp "${TMPDIR:-/tmp}/wrap-adopt-dry.XXXXXX")"
  ADOPT_DRY="$("$ADOPT_SH" --dry-run "$repo" 2>"$drf")"; drc=$?
  [ "$drc" -eq 0 ] || _pf_add "adopt --dry-run: $(tail -n 1 "$drf")"
  rm -f "$drf"
  style="$(printf '%s' "$ADOPT_DRY" | sed -n 's/.*set outputStyle=\([^ ]*\).*/\1/p' | sed -n '1p')"
  ADOPT_STYLE="$style"

  # R3k: an ignored adoption path never reaches the index under `git add -A`. Plain
  # check-ignore: a tracked path answers 1 and still stages, so it passes; the
  # style file joins only when the dry run reports one (repos ignore .claude/* and
  # re-include .claude/settings.json).
  for p in AGENTS.md CLAUDE.md WORKFLOW.md .kit.toml docs/verification/README.md .claude/settings.json; do
    git -C "$repo" check-ignore -q -- "$p" 2>/dev/null && _pf_add "$p is gitignored"
  done
  if [ -n "$style" ] \
     && git -C "$repo" check-ignore -q -- ".claude/output-styles/${style}.md" 2>/dev/null; then
    _pf_add ".claude/output-styles/${style}.md is gitignored"
  fi

  # The reads above see HEAD and the tracking ref as last fetched; say so when they
  # disagree, before a `would adopt` row is trusted.
  if [ "$main_co" = 1 ] && [ -n "$def" ] && _ref_exists "$repo" "refs/remotes/origin/$def"; then
    [ "$(git -C "$repo" rev-parse HEAD 2>/dev/null)" \
      = "$(git -C "$repo" rev-parse "refs/remotes/origin/$def" 2>/dev/null)" ] \
      || PF_NOTE="note: main checkout differs from origin/$def as last fetched"
  fi

  [ -z "$PF_REASONS" ] || PF_STATUS="refused"
  PF_DEF="$def"
  return 0
}

# --------------------------------------------------------------------------- apply

# _adopt_one <repo> <def> <body-file> -- the apply path for one preflight-clean
# repo, R5's order with a stop at the first failure: cmd_start, the file writer
# (WRAP_ADOPT_SH under the test flag, else $ADOPT_SH), `git add -A`, the R6 path
# and ignored-path guards, R6a, the commit, R6b's recheck, R7's override, land
# under R9's streamed capture, and R8's parse (with the counted merge's
# `adopt.sh --check` on the main checkout). start and land are functions of this
# script, never the bin/wrap entry. The verb never removes what a failure
# leaves: after cmd_start every failure row names the worktree, and R12 decides
# whether a `resume:` line can follow. Sets ADOPT_ROW, ADOPT_PR (`#<n>` or `-`),
# and ADOPT_STOP (1 on the land-pipeline interrupt); always returns 0.
_adopt_one() {
  local repo="$1" def="$2" bodyfile="$3"
  local wt="" out rc style mb miss detail log land_rc merged prn line fl driver ig
  ADOPT_ROW=""; ADOPT_PR="-"; ADOPT_STOP=0

  wt="$(cmd_start "$repo" "$ADOPT_BRANCH" 2>"$ADOPT_TMP/start.err")"; rc=$?
  if [ "$rc" -ne 0 ]; then
    ADOPT_ROW="failed: start: $(tail -n 1 "$ADOPT_TMP/start.err" 2>/dev/null)"
    return 0
  fi
  ADOPT_WT="$wt"

  driver="$ADOPT_SH"
  if [ "${WRAP_ADOPT_TEST:-0}" = "1" ] && [ -n "${WRAP_ADOPT_SH:-}" ]; then
    driver="$WRAP_ADOPT_SH"
  fi
  out="$("$driver" "$wt" 2>&1)"; rc=$?
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/    /'
  if [ "$rc" -ne 0 ]; then
    ADOPT_ROW="failed: adopt exit ${rc}; worktree left at ${wt}"
    return 0
  fi

  out="$(git -C "$wt" add -A 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    ADOPT_ROW="failed: git add: $(printf '%s\n' "$out" | tail -n 1); worktree left at ${wt}"
    return 0
  fi

  # R6: every staged path must sit inside ADOPT_PATHS; the one allowed
  # output-styles path is named by the staged settings' own outputStyle.
  style="$(_adopt_style_of "$wt" ":")"
  miss="$(git -C "$wt" diff --cached --name-only --no-renames -z | _adopt_paths_miss "$style")"
  if [ -n "$miss" ]; then
    ADOPT_ROW="failed: adoption wrote ${miss}, outside the scaffold set; worktree left at ${wt}"
    return 0
  fi
  # R6's in-worktree ignored check, before the empty-list test: the worktree is
  # built from fresh origin/<def>, whose ignore rules R3k's main-checkout read
  # can miss. git prints a collapsed directory (`!! .claude/`) when one is
  # ignored whole.
  ig="AGENTS.md CLAUDE.md WORKFLOW.md .kit.toml docs/verification/README.md .claude/settings.json"
  [ -n "$style" ] && ig="$ig .claude/output-styles/${style}.md"
  miss="$(git -C "$wt" status --porcelain --ignored -- $ig 2>/dev/null | sed -n 's/^!! //p' | sed -n 1p)"
  if [ -n "$miss" ]; then
    ADOPT_ROW="failed: adoption path ${miss} is gitignored in origin/${def}; worktree left at ${wt}"
    return 0
  fi
  if [ -z "$(git -C "$wt" diff --cached --name-only --no-renames)" ]; then
    ADOPT_ROW="no change: origin/${def} already carries the adoption; worktree left at ${wt}"
    return 0
  fi
  # R6a: the one executable-bearing file may gain kit hooks and outputStyle only.
  if [ -n "$(git -C "$wt" diff --cached --name-only --no-renames -- .claude/settings.json)" ]; then
    if ! detail="$(_adopt_settings_diff "$(_adopt_blob "$wt" ":.claude/settings.json")" \
                                        "$(_adopt_blob "$wt" "origin/${def}:.claude/settings.json")")"; then
      ADOPT_ROW="failed: adoption changed .claude/settings.json beyond kit hooks: ${detail}; worktree left at ${wt}"
      return 0
    fi
  fi

  out="$(git -C "$wt" commit -q -m "$ADOPT_COMMIT_SUBJECT" -m "$ADOPT_COMMIT_BODY" 2>&1)"; rc=$?
  if [ "$rc" -ne 0 ]; then
    ADOPT_ROW="failed: commit: $(printf '%s\n' "$out" | tail -n 1); worktree left at ${wt}"
    return 0
  fi

  # R6b: a target-repo commit hook can rewrite or add to the commit after the
  # staged guard ran, so R6 and R6a run again on the committed diff.
  miss=""
  if [ -n "$(git -C "$wt" status --porcelain)" ]; then
    miss="$(git -C "$wt" status --porcelain | sed -n '1{s/^...//;p;}')"
  else
    mb="$(git -C "$wt" merge-base "origin/${def}" HEAD 2>/dev/null)"
    if [ -n "$mb" ]; then
      miss="$(_adopt_commit_guard "$wt" HEAD "$mb")"
    else
      miss="merge-base of origin/${def} and HEAD unresolved"
    fi
  fi
  if [ -n "$miss" ]; then
    ADOPT_ROW="failed: the commit differs from the guarded set: ${miss}; worktree left at ${wt}"
    return 0
  fi

  # R7: the logged override stands in for the proof of done the ship-gate never
  # sees (G4). It runs inside the worktree so the entry is keyed to this repo,
  # and before land so a failed log stops the merge (DEC-Q).
  out="$(cd "$wt" && bash "$PROOF_LEDGER_SH" override "${ADOPT_BRANCH#*/}" "$OVERRIDE_REASON" 2>&1)"; rc=$?
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^/    /'
  if [ "$rc" -ne 0 ]; then
    ADOPT_ROW="failed: override: $(printf '%s\n' "$out" | tail -n 1); resume: wrap land ${wt}${bodyfile:+ --body-file $bodyfile}"
    return 0
  fi

  # R9: land streams to the terminal AND a temp file R8 parses. tee -i so a
  # Ctrl-C reaches land while the capture keeps its last lines; PIPESTATUS[0] is
  # land's own exit where $? would be tee's.
  log="$ADOPT_TMP/land.log"; : > "$log"
  if [ -n "$bodyfile" ]; then
    cmd_land "$wt" --body-file "$bodyfile" 2>&1 | tee -i "$log"; land_rc=${PIPESTATUS[0]}
  else
    cmd_land "$wt" 2>&1 | tee -i "$log"; land_rc=${PIPESTATUS[0]}
  fi

  # R8: land's exit code first, then the captured lines. A merge counts only on
  # land's exact `tree verified` line.
  merged="$(grep -E 'merged #[0-9]+ \([0-9a-f]+\): tree verified' "$log" | sed -n 1p)"
  prn="$(sed -n 's/.*\(#[0-9][0-9]*\).*/\1/p' "$log" | sed -n 1p)"
  [ -n "$prn" ] && ADOPT_PR="$prn"
  case "$land_rc" in
    130|143)
      ADOPT_ROW="interrupted: land exit ${land_rc}; read ${wt}"; ADOPT_STOP=1; return 0 ;;
    3)
      line="$(grep 'merged #' "$log" | grep -v 'tree verified' | sed -n '1{s/^ *//;p;}')"
      ADOPT_ROW="failed: land exit 3: ${line}; worktree left at ${wt}"
      return 0 ;;
  esac
  if [ -n "$merged" ]; then
    if "$ADOPT_SH" --check "$repo" >/dev/null 2>&1; then
      ADOPT_ROW="adopted"
      fl="$(grep -E 'FAILED ' "$log" | sed -n '1{s/^ *//;p;}')"
      [ -n "$fl" ] && ADOPT_ROW="adopted; ${fl}"
    else
      fl="$(grep -F 'PULL BLOCKED' "$log" | sed -n '1{s/^ *//;p;}')"
      [ -z "$fl" ] && fl="adopt --check exit 1"
      ADOPT_ROW="merged, not adopted on the main checkout: ${fl}"
    fi
    return 0
  fi
  # Any line naming `wrap merge` is land's CONFLICTING-cycle advice: a merge
  # commit is already on origin, so the row quotes it and adds no `resume:`.
  fl="$(grep -F 'wrap merge' "$log" | sed -n '1{s/^ *//;p;}')"
  if [ -n "$fl" ]; then
    ADOPT_ROW="failed: land exit ${land_rc}: ${fl}"
    return 0
  fi
  fl="$(grep -E 'REFUSED|FAILED' "$log" | sed -n '1{s/^ *//;p;}')"
  [ -z "$fl" ] && fl="$(tail -n 1 "$log" | sed 's/^ *//')"
  ADOPT_ROW="failed: land exit ${land_rc}: ${fl}; resume: wrap land ${wt}${bodyfile:+ --body-file $bodyfile}"
  return 0
}

# --------------------------------------------------------------------------- adopt

# _adopt_summary -- R10's closing table, one row per repo in argument order:
# basename, PR (`#<n>` or `-`), result.
_adopt_summary() {
  local i=0 nw=0 pw=1
  while [ "$i" -lt "$ADOPT_N" ]; do
    i=$(( i + 1 ))
    [ "${#ADOPT_NAMES[$i]}" -gt "$nw" ] && nw=${#ADOPT_NAMES[$i]}
    [ "${#ADOPT_PRS[$i]}" -gt "$pw" ] && pw=${#ADOPT_PRS[$i]}
  done
  echo "ADOPT SUMMARY"
  i=0
  while [ "$i" -lt "$ADOPT_N" ]; do
    i=$(( i + 1 ))
    printf '  %-*s  %-*s  %s\n' "$nw" "${ADOPT_NAMES[$i]}" "$pw" "${ADOPT_PRS[$i]}" "${ADOPT_ROWS[$i]}"
  done
}

# _adopt_trap <INT|TERM> -- R10: a signal to the verb's own process. bash defers
# it until the running foreground command ends, so it lands here between
# commands; the running repo reads interrupted, every later repo `not run`,
# then the summary and R11's exit 1. A signal that reaches only land's
# pipeline subshell never gets here (traps reset in a subshell); R8 rows it.
_adopt_trap() {
  local j="$ADOPT_I"
  ADOPT_ROWS[$j]="interrupted"
  [ -n "$ADOPT_WT" ] && ADOPT_ROWS[$j]="interrupted: $1; read $ADOPT_WT"
  ADOPT_PRS[$j]="-"
  printf '  result: - %s\n' "${ADOPT_ROWS[$j]}"
  while [ "$j" -lt "$ADOPT_N" ]; do
    j=$(( j + 1 ))
    ADOPT_ROWS[$j]="not run"; ADOPT_PRS[$j]="-"
  done
  _adopt_summary
  exit 1
}

# cmd_adopt [--apply] [--body-file F] <repo> [<repo>...] -- R1/R4/R10/R11: repos
# run one at a time in argument order, a refusal or failure never stops the
# next, an interrupt (R8's land-pipeline row, or the INT/TERM trap) stops the
# batch with `not run` rows, and the run ends with the ADOPT SUMMARY table.
cmd_adopt() {
  local apply=0 bodyfile="" nrepos=0 arg i crepo row gh_state
  local -a repos=()

  while [ $# -gt 0 ]; do
    arg="$1"
    case "$arg" in
      --apply) apply=1; shift ;;
      --body-file)
        shift
        [ $# -gt 0 ] || { echo "wrap.sh adopt: --body-file needs a value" >&2; return 64; }
        bodyfile="$1"; shift ;;
      -*) echo "wrap.sh adopt: unknown flag '${arg}'" >&2; return 64 ;;
      *)
        _reject_packed adopt "$arg" || return 64
        nrepos=$(( nrepos + 1 )); repos[$nrepos]="$arg"; shift ;;
    esac
  done
  [ "$nrepos" -gt 0 ] \
    || { echo "usage: wrap.sh adopt [--apply] [--body-file F] <repo> [<repo>...]" >&2; return 64; }
  if [ -n "$bodyfile" ]; then
    [ -f "$bodyfile" ] \
      || { echo "wrap.sh adopt: --body-file ${bodyfile} does not exist" >&2; return 64; }
    # One body written for one repo's PR template is wrong for the next.
    [ "$nrepos" -eq 1 ] \
      || { echo "wrap.sh adopt: --body-file takes exactly one repo" >&2; return 64; }
  fi

  # R4: one gh read per batch; not ok refuses every repo before any work.
  gh_state="$(_gh_state)"

  ADOPT_TMP="$(mktemp -d "${TMPDIR:-/tmp}/wrap-adopt.XXXXXX")"
  trap '[ -n "${ADOPT_TMP:-}" ] && rm -rf "$ADOPT_TMP"' EXIT

  local failed=0 stopped=0 prcol="-"
  ADOPT_N="$nrepos"; ADOPT_I=1
  i=0
  while [ "$i" -lt "$nrepos" ]; do
    i=$(( i + 1 ))
    crepo="$(cd "${repos[$i]}" 2>/dev/null && pwd -P)" || crepo="${repos[$i]}"
    ADOPT_REPOS[$i]="$crepo"; ADOPT_NAMES[$i]="$(basename "$crepo")"
  done
  trap '_adopt_trap INT' INT
  trap '_adopt_trap TERM' TERM

  i=0
  while [ "$i" -lt "$nrepos" ]; do
    i=$(( i + 1 ))
    ADOPT_I="$i"; ADOPT_WT=""
    crepo="${ADOPT_REPOS[$i]}"
    printf '== %s\n' "$crepo"
    prcol="-"
    if [ "$stopped" = 1 ]; then
      row="not run"
    elif [ "$gh_state" != "ok" ]; then
      row="refused: gh is ${gh_state}"
    else
      _adopt_preflight "$crepo" "$bodyfile"
      [ -z "$ADOPT_DRY" ] || printf '%s\n' "$ADOPT_DRY" | sed 's/^/    /'
      [ -z "$PF_NOTE" ] || printf '    %s\n' "$PF_NOTE"
      case "$PF_STATUS" in
        skip)    row="skip: already adopted" ;;
        refused) row="refused: ${PF_REASONS}" ;;
        *)
          if [ "$apply" = 1 ]; then
            _adopt_one "$crepo" "$PF_DEF" "$bodyfile"
            row="$ADOPT_ROW"; prcol="$ADOPT_PR"
            [ "$ADOPT_STOP" = 1 ] && stopped=1
          else
            row="would adopt"
          fi ;;
      esac
    fi
    case "$row" in
      "would adopt"|"skip: already adopted"|"adopted") ;;
      *) failed=1 ;;
    esac
    ADOPT_ROWS[$i]="$row"; ADOPT_PRS[$i]="$prcol"
    printf '  result: %s %s\n' "$prcol" "$row"
  done
  _adopt_summary
  return "$failed"
}
