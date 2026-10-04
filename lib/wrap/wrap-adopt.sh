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
KIT_HOOK_RE='\Abash \$HOME/\.claude/dwarves-kit/hooks/(anchor-root\.sh \$HOME/\.claude/dwarves-kit/hooks/)?[A-Za-z0-9_-]+\.sh( --[a-z][a-z-]*)*\z'

# The file writer preflight always runs. WRAP_ADOPT_SH replaces it for the apply
# path's R5 call alone, and only under WRAP_ADOPT_TEST=1 (an unflagged inherited
# value must never swap the writer that runs right before an override and a merge);
# T1b owns that call site.
ADOPT_SH="$LIB_ROOT/adopt.sh"

PF_STATUS=""
PF_REASONS=""
PF_NOTE=""
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
  local ono=0 wtp=0 rebase_seen=0

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
        # T1b puts the R6/R6a leftover check in front of this `resume:`.
        _pf_add "resume: wrap land $wt${bodyfile:+ --body-file $bodyfile}"
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
  return 0
}

# --------------------------------------------------------------------------- adopt

# cmd_adopt [--apply] [--body-file F] <repo> [<repo>...] -- R1/R4/R11. The dry-run
# loop is T1a's; _adopt_one and the apply batch arrive in T1b/T1c.
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

  local failed=0
  i=0
  while [ "$i" -lt "$nrepos" ]; do
    i=$(( i + 1 ))
    crepo="$(cd "${repos[$i]}" 2>/dev/null && pwd -P)" || crepo="${repos[$i]}"
    printf '== %s\n' "$crepo"
    if [ "$gh_state" != "ok" ]; then
      row="refused: gh is ${gh_state}"
    else
      _adopt_preflight "$crepo" "$bodyfile"
      case "$PF_STATUS" in
        skip)    row="skip: already adopted" ;;
        refused) row="refused: ${PF_REASONS}" ;;
        *)
          if [ "$apply" = 1 ]; then
            # _adopt_one lands in T1b; an apply-ready repo is reported, never run.
            row="failed: apply not built yet; nothing was written"
          else
            row="would adopt"
          fi ;;
      esac
      [ -z "$ADOPT_DRY" ] || printf '%s\n' "$ADOPT_DRY" | sed 's/^/    /'
      [ -z "$PF_NOTE" ] || printf '    %s\n' "$PF_NOTE"
    fi
    case "$row" in
      "would adopt"|"skip: already adopted"|"adopted") ;;
      *) failed=1 ;;
    esac
    printf '  result: - %s\n' "$row"
  done
  return "$failed"
}
