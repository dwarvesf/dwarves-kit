#!/usr/bin/env bash
# report-lint.sh -- the `Needs you` admission test, mechanised.
#
# `commands/wrap.md` step 9 says an item belongs in `Needs you` only when the operator is
# the ONLY one who can do it. That rule was prose, and prose lost: a finished green PR kept
# getting parked there as "say go and I merge it", which costs a round trip and buys nothing.
#
# This reads a wrap report and fails when a `Needs you` item asks PERMISSION instead of
# naming a BLOCKER. It cannot judge whether an action is truly irreversible, so it does not
# try. It catches the one shape that is always wrong: an item whose own text offers to do
# the work itself.
#
# It also enforces that step 7b reported an outcome at all. Step 7b (build the candidates
# this session produced, rather than proposing them) used to be the one step that left no
# trace when skipped, and no trace when it ran and found nothing. Those two outcomes were
# indistinguishable in the report, so skipping it was invisible: it was skipped in a real
# 20-hour session on 2026-09-09 and only caught because the operator asked. Every other step
# leaves evidence, a board flip, a merge sha, an activity line. This one now owes a `Built:`
# line naming which of three things happened, so "did not run" can never read as "found
# nothing". That distinction is the same one in
# ops-toolkit/research/2026-09-09-checks-need-a-third-state.md, and this file had the bug.
#
# Usage: report-lint.sh [<file>]   (reads stdin when no file is given)
# Exit:  0 clean, 1 a finding (each printed as `line <n>: <reason>` on stderr), 2 usage.

set -uo pipefail

# Permission-seeking phrasing. An item carrying any of these is offering to act, which means
# the actor is the agent, not the operator, which means the item fails the admission test.
# Anchored to whole words so "approve" does not match "approved by legal" style prose... it
# does, deliberately: an item that needs someone's approval names the BLOCKER (who must
# approve), and that phrasing survives because the blocker is a person, not the operator's yes.
PERMISSION_RE='say (the word|go)|just say|let me know if|want me to|shall i |should i |can i go ahead|and i will (merge|apply|run|push|do)|and i can (merge|apply|run|push)|confirm and i|give me the (word|go)|ready when you are|approve\?|ok to (merge|proceed|apply|push)\?|proceed\?'

# Verbs the kit runs for itself. A `Needs you` item built around one of these is suspect,
# but not always wrong (a merge really can be blocked on a human), so this is a WARN.
SELF_RUNNABLE_RE='gh pr merge|gh workflow run|gh run (watch|rerun)|git (pull|push|merge)\b|git branch -[dD]|git worktree remove|chezmoi apply|npm (test|install)\b|pytest\b'

# Targets that hold PROSE. `bin/precedent` indexes memory notes and research files as hit
# kinds, so a step 7b whose top hit is a note turns a build into a write and still reports
# `ENHANCE <repo> .claude/memory/foo.md`, which satisfies every other rule here. The word
# `memory` as its own path segment covers `.claude/memory/` and the bare `MEMORY.md` index,
# and the phrase "machine memory" that reports use for the per-project store.
PROSE_TARGET_RE='(^|/|[[:space:]])memory([/.]|[[:space:]]|$)|(^|/|[[:space:]])research/|_meta/handoffs/'

# The escape hatch for a session where no mechanism was possible. The reason must be long
# enough to be a reason: an empty or one-word token would silence the rule for free.
PROSE_ONLY_MIN_REASON=12

# Markers that name a real blocker. Their presence downgrades a SELF_RUNNABLE warn to clean:
# the item is not asking permission, it is reporting what stands in the way.
BLOCKER_RE='blocked (on|by)|waiting on|needs? (your|a) (password|credential|2fa|approval from|signature)|only you can|requires (a )?human|cannot (run|reach|access)|no (credential|access|token)|fails? with|permission denied'

_usage() { echo "usage: report-lint.sh [<file>]   (stdin when no file)" >&2; exit 2; }

src="${1:-}"
if [ -n "$src" ]; then
  [ -f "$src" ] || { echo "report-lint.sh: not a file: $src" >&2; exit 2; }
  case "$src" in -h|--help) _usage ;; esac
  input="$(cat "$src")"
else
  input="$(cat)"
fi

# A follow-through report (commands/wrap.md step 10) is the second report of one pass. Its
# first `## ` heading is `## Follow-through:`. It owes no `**Seam:**` line, because the seams
# ran in the first report, and it is the one report where a full-lane item may close as built:
# step 10 builds it as a draft PR and never merges it, so the item closes as `#<pr> DRAFT`
# and must pair with a lettered `REVIEW #<pr>` item in `Needs you`. Every other rule applies to it unchanged.
follow_report=0
first_h2="$(printf '%s\n' "$input" | grep -m1 '^## ' || true)"
case "$first_h2" in '## Follow-through:'*) follow_report=1 ;; esac

# PR numbers named by `Needs you` items that open with REVIEW, space-separated, filled by the
# walk below. A full-lane build in a follow-through report must name one of them.
review_prs=" "

# Walk the report. `in_block` is on between the `Needs you` header and the next bold section
# header, so only that section is judged; a `What happened` sentence may say anything.
findings=0
warns=0
lineno=0
in_block=0
while IFS= read -r line; do
  lineno=$((lineno + 1))
  case "$line" in
    *'**Needs you:**'*) in_block=1; continue ;;
  esac
  [ "$in_block" = 1 ] || continue
  # Any other bold section header closes the block.
  case "$line" in
    '**'*'**'*) in_block=0; continue ;;
  esac
  # Only lettered items are judged; blank lines and the NOTHING sentinel are fine.
  case "$line" in
    [a-z].\ *) : ;;
    *) continue ;;
  esac

  # Only the number right after `REVIEW #` counts, so `REVIEWED` and a second `#N` later in
  # the sentence never whitelist a PR.
  _r_pr="$(printf '%s' "${line#[a-z]. }" | sed -nE 's/^REVIEW #([0-9]+)([^0-9].*)?$/\1/p')"
  [ -n "$_r_pr" ] && review_prs="${review_prs}${_r_pr} "

  lower="$(printf '%s' "$line" | tr '[:upper:]' '[:lower:]')"

  if printf '%s' "$lower" | grep -qE "$PERMISSION_RE"; then
    echo "line ${lineno}: asks permission instead of naming a blocker; run it and report it in What happened" >&2
    echo "  ${line}" >&2
    findings=$((findings + 1))
    continue
  fi

  if printf '%s' "$lower" | grep -qE "$SELF_RUNNABLE_RE" && ! printf '%s' "$lower" | grep -qE "$BLOCKER_RE"; then
    echo "warn line ${lineno}: names a command the kit can run, with no blocker stated" >&2
    echo "  ${line}" >&2
    warns=$((warns + 1))
  fi
done <<< "$input"

# Step 7b coverage. The line must be present AND carry one of the three outcomes, so an
# empty `**Built:**` header cannot satisfy it. A named item says what was built or reported;
# NOTHING says the precedent check ran and produced no candidate; SKIPPED says the step did
# not run and why. A report with no such line means nobody can tell which happened.
#
# BUILT itself comes in two forms. INLINE keeps one candidate on the header line, the
# original shape. LIST is a bare `**Built:**` header followed by `- ` bullets, one candidate
# per line, added because a real session crammed three candidates onto one line joined by
# nothing readable. Both forms carry the same per-candidate rule below; LIST just applies it
# once per bullet instead of once per line, which is the whole point of the form: a report
# with a bare path and a commit buried as the second of three items used to slip through
# because only the first item on the line got read closely.
if ! printf '%s' "$input" | grep -q '\*\*Built:\*\*'; then
  echo "line 0: no '**Built:**' line; step 7b (build the candidates) owes an outcome" >&2
  echo "  add one of: '**Built:** <what>', '**Built:** NOTHING: no candidates', '**Built:** SKIPPED: <why>', or a bare '**Built:**' header followed by '- ' bullets" >&2
  findings=$((findings + 1))
else
  # Split the block: built_inline is whatever trails the header on its own line; built_bullets
  # is every immediately-following `- ` line, up to the first blank line or the next bold
  # header. A header with neither is empty; a header with both is two grammars fighting over
  # one line, never valid (NOTHING and SKIPPED are whole-outcome states and stay inline, per
  # the rule below).
  built_inline=""
  built_bullets=()
  built_items=()      # every candidate, inline or bullet, for the prose rule below
  prose_only_line=""  # the PROSE-ONLY escape, wherever it appeared
  _b_state=0   # 0 = looking for the header, 1 = header seen, scanning bullets
  while IFS= read -r _b_line; do
    if [ "$_b_state" = 0 ]; then
      case "$_b_line" in
        *'**Built:**'*)
          built_inline="$(printf '%s' "$_b_line" | sed 's/^.*\*\*Built:\*\*[[:space:]]*//')"
          _b_state=1
          ;;
      esac
      continue
    fi
    case "$_b_line" in
      '- '*) built_bullets+=("${_b_line#- }") ;;
      *) _b_state=2 ;;
    esac
    [ "$_b_state" = 2 ] && break
  done <<< "$input"
  built_bullet_count=${#built_bullets[@]}

  if [ -z "$built_inline" ] && [ "$built_bullet_count" -eq 0 ]; then
    echo "line 0: '**Built:**' is empty; name what was built, or NOTHING, or SKIPPED with a reason, or list '- ' bullets" >&2
    findings=$((findings + 1))
  elif [ -n "$built_inline" ] && [ "$built_bullet_count" -gt 0 ]; then
    echo "line 0: '**Built:**' carries both inline content and bullets; NOTHING, SKIPPED, and a single inline candidate stay on the header line and are never mixed with a bullet list" >&2
    echo "  ${built_inline}" >&2
    findings=$((findings + 1))
  elif [ "$built_bullet_count" -gt 0 ]; then
    # LIST form. The three-state rule (NOTHING/SKIPPED/named) is a whole-outcome call already
    # made by staying inline above, so every bullet here is a candidate and owes the same
    # ENHANCE/NEW token the inline form owes, checked per bullet so one bad item among several
    # good ones cannot hide.
    _b_idx=0
    for _b_item in "${built_bullets[@]}"; do
      _b_idx=$((_b_idx + 1))
      # The escape hatch takes its own bullet. It is not a candidate, so it owes no token.
      case "$_b_item" in
        PROSE-ONLY:*) prose_only_line="$_b_item"; continue ;;
      esac
      built_items+=("$_b_item")
      _b_item_lower="$(printf '%s' "$_b_item" | tr '[:upper:]' '[:lower:]')"
      case "$_b_item_lower" in
        *enhance*|*new\ \(*) : ;;
        *)
          echo "line 0: '**Built:**' bullet ${_b_idx} names something built with no ENHANCE <home> or NEW (precedent: ...) token; name the existing tool it joins, or the precedent miss" >&2
          echo "  - ${_b_item}" >&2
          findings=$((findings + 1)) ;;
      esac
    done
  else
    # INLINE form. `SKIPPED: nothing to build` says the step did not run AND that it found
    # nothing, which is two states in one line and means neither; it appeared thirteen times
    # in two weeks of real reports, every one from a step that never scanned. An empty scan is
    # NOTHING. And a non-empty line must carry ENHANCE or NEW: those tokens are the slot that
    # forces naming the existing tool a candidate joins. A `Built:` that is only a path and a
    # commit is the session's own deliverable wearing step 7b's label, which is how the step
    # reported "built" every session and enhanced nothing.
    built_lower="$(printf '%s' "$built_inline" | tr '[:upper:]' '[:lower:]')"
    case "$built_lower" in
      skipped:*nothing*|skipped:*no\ candidate*|skipped:*none*)
        echo "line 0: '**Built:** SKIPPED: ...' says the step did not run; an empty scan is 'NOTHING: no candidates', not a skip" >&2
        echo "  ${built_inline}" >&2
        findings=$((findings + 1)) ;;
      nothing*|skipped:*) : ;;
      *enhance*|*new\ \(*)
        # INLINE carries the escape appended after the candidate, on the same line.
        case "$built_inline" in
          *PROSE-ONLY:*) prose_only_line="PROSE-ONLY:$(printf '%s' "$built_inline" | sed 's/^.*PROSE-ONLY://')" ;;
        esac
        built_items+=("$built_inline") ;;
      *)
        echo "line 0: '**Built:**' names something built with no ENHANCE <home> or NEW (precedent: ...) token; name the existing tool it joins, or the precedent miss" >&2
        echo "  ${built_inline}" >&2
        findings=$((findings + 1)) ;;
    esac
  fi

  # Verdict first. A candidate line that reads "<label> ENHANCE <home> ... memory note written"
  # passed for shipped work on 2026-09-16 because nothing on it said whether anything landed.
  # Each item now opens with what happened, in caps, before what it was.
  #
  # STAGED and FILED are retired verdicts. Step 7b used to close an unbuilt candidate by
  # writing a staging block or minting a board row, and one estate board grew 13 to 25 rows a
  # day that way while its staging file held dozens of undrained blocks. A candidate the
  # session does not build is REPORTED here and nowhere else; a board row is the operator's
  # call, never a side effect of the wrap.
  _v_idx=0
  for _v_item in "${built_items[@]}"; do
    _v_idx=$((_v_idx + 1))
    case "$_v_item" in
      REPORTED\ *)
        # A tool that already does the whole job leaves nothing to build, so REPORTED hands
        # step 10 an empty item and the next session hand-rolls the same code. The missing
        # piece is the path to the tool: NOTE, with the pointer written this session.
        _v_why="$(printf '%s' "$_v_item" | sed -nE 's/.*[(,][[:space:]]*reported:(.*)$/\1/p' | tr '[:upper:]' '[:lower:]')"
        case "$_v_why" in
          *'already covers'*|*'nothing missing'*)
            echo "line 0: '**Built:**' item ${_v_idx} is REPORTED but its tool already covers it; close it as NOTE with the pointer written (a skill trigger, the tool's README or quick-ref entry, or a memory note) and name that file" >&2
            echo "  - ${_v_item}" >&2
            findings=$((findings + 1)) ;;
        esac ;;
      BUILT\ *|NOTE\ *) : ;;
      STAGED\ *|FILED\ *)
        echo "line 0: '**Built:**' item ${_v_idx} uses a retired verdict; step 7b never stages or files a row, so a candidate not built here is REPORTED" >&2
        echo "  - ${_v_item}" >&2
        findings=$((findings + 1)) ;;
      *)
        echo "line 0: '**Built:**' item ${_v_idx} has no verdict; start it with BUILT, REPORTED, or NOTE so the reader sees what happened before what it was" >&2
        echo "  - ${_v_item}" >&2
        findings=$((findings + 1)) ;;
    esac
  done

  # Lane closure. The lane token says only that the candidate was SIZED. What became of it is
  # the other half, one of two words: `verified:` for a build that happened here, or
  # `reported:` with a one-line why for one left in the report. An item carrying a lane and
  # neither reports a classification and no outcome, which is the same hole the `**Built:**`
  # line itself exists to close, one level down. The retired closures (`staged`, `filed:`,
  # `capture failed:`) no longer count. The closure must also match the verdict: BUILT owes
  # `verified:`, REPORTED owes `reported:`, and `lane=full` is never BUILT here, because that
  # lane owes a spec and a review. The token is anchored to the suffix's own `(` or `,` so
  # `reported:` inside free text or `unreported:` never counts.
  if [ "${#built_items[@]}" -gt 0 ]; then
    _l_idx=0
    for _l_item in "${built_items[@]}"; do
      _l_idx=$((_l_idx + 1))
      printf '%s' "$_l_item" | grep -qE 'lane=[a-z]+' || continue
      _l_close=""
      printf '%s' "$_l_item" | grep -qE '[(,][[:space:]]*verified:' && _l_close="verified"
      printf '%s' "$_l_item" | grep -qE '[(,][[:space:]]*reported:' && _l_close="${_l_close:+$_l_close+}reported"
      _l_want=""
      case "$_l_item" in BUILT\ *) _l_want="verified" ;; REPORTED\ *) _l_want="reported" ;; esac
      if [ -z "$_l_close" ]; then
        echo "line 0: '**Built:**' item ${_l_idx} names a lane with no closure; add 'verified: <check>, <commit or PR>' for a build, or 'reported: <one-line why>' for one left in the report" >&2
      elif printf '%s' "$_l_item" | grep -qE 'lane=full' && [ "$_l_close" != "reported" ]; then
        if [ "$follow_report" = 1 ] && [ "$_l_close" = "verified" ]; then
          # Step 10 built it; the only valid close is an open PR the operator reviews.
          _l_reviewed=0
          for _l_pr in $(printf '%s' "$_l_item" | grep -oE '#[0-9]+ DRAFT' | tr -dc '0-9 \n'); do
            case "$review_prs" in *" ${_l_pr} "*) _l_reviewed=1 ;; esac
          done
          [ "$_l_reviewed" = 1 ] && continue
          echo "line 0: '**Built:**' item ${_l_idx} is a full-lane build that is not a '#<pr> DRAFT' named by a 'REVIEW #<pr>' item in Needs you; wrap never merges a full-lane PR, the operator reviews its design first" >&2
        else
          echo "line 0: '**Built:**' item ${_l_idx} closes a full-lane candidate as built; a full lane is never built at session close, report it with 'reported: <why>'" >&2
        fi
      elif [ -n "$_l_want" ] && [ "$_l_close" != "$_l_want" ]; then
        echo "line 0: '**Built:**' item ${_l_idx} pairs its verdict with the wrong closure; BUILT owes 'verified:', REPORTED owes 'reported:'" >&2
      else
        continue
      fi
      echo "  ${_l_item}" >&2
      findings=$((findings + 1))
    done
  fi

  # A precedent hit on a NOTE is not a build. `bin/precedent` indexes memory notes and
  # research files as hit kinds, so when the top hit is prose the step silently turns a build
  # into a write, and the ENHANCE token above accepts it. That happened on 2026-09-10: a
  # procedure run six times by hand, which had already cost a bad production deploy, produced
  # two memory notes and one research note and zero mechanism. The same precedent output also
  # named the code that owned the procedure, one line below the note, and the real fix landed
  # in that file later. So a prose home and a code home in one hit list resolve to the code
  # home. This runs only on a Built that already passed the per-item token rule, so it judges
  # well formed items only.
  if [ "${#built_items[@]}" -gt 0 ]; then
    prose_count=0
    for _p_item in "${built_items[@]}"; do
      _p_target="$(printf '%s' "$_p_item" \
        | sed -E 's/^.*NEW \(precedent: [^)]*\): *//; s/^.*ENHANCE +//; s/PROSE-ONLY:.*$//; s/[[:space:]]*\([^)]*\)[[:space:]]*$//' \
        | tr '[:upper:]' '[:lower:]')"
      if printf '%s' "$_p_target" | grep -qE "$PROSE_TARGET_RE"; then
        prose_count=$((prose_count + 1))
      fi
    done
    if [ "$prose_count" -eq "${#built_items[@]}" ]; then
      prose_reason=""
      case "$prose_only_line" in
        PROSE-ONLY:*)
          prose_reason="$(printf '%s' "${prose_only_line#PROSE-ONLY:}" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')" ;;
      esac
      if [ "${#prose_reason}" -lt "$PROSE_ONLY_MIN_REASON" ]; then
        echo "line 0: every '**Built:**' item targets prose (a memory note, a research file, a handoff); a precedent hit on a note is not a build" >&2
        echo "  a note is where the lesson goes AFTER a build, never instead of the build" >&2
        echo "  when precedent returns both a prose home and a code home, the code home wins" >&2
        echo "  if no mechanism was possible here, say why: add a 'PROSE-ONLY: <reason>' bullet, or append the token to the inline item, with at least ${PROSE_ONLY_MIN_REASON} characters of reason" >&2
        findings=$((findings + 1))
      fi
    fi
  fi
fi

# A `NEW (precedent: nothing matched)` candidate is a fresh script by definition, no home to
# join. But if it turns out to speak CDP, it already has a home: browser-harness-js's
# per-site learnings. Warn only (the precedent check ran and genuinely found nothing to
# ENHANCE; this catches the narrower case where the candidate duplicates the harness itself).
# This walks every line of the input, so it fires the same way on an inline `Built:` line and
# on a LIST-form bullet: the token match does not care which grammar carried it.
HARNESS_CDP_RE='session\.(Runtime|Input|DOM|Page|Target)\.|listPageTargets\(|Runtime\.evaluate'
while IFS= read -r built_new_line; do
  case "$built_new_line" in
    *'NEW (precedent: nothing matched):'*) : ;;
    *) continue ;;
  esac
  new_path="$(printf '%s' "$built_new_line" | sed -n 's/.*NEW (precedent: nothing matched): *//p')"
  new_path="$(printf '%s' "$new_path" | sed -E 's/[[:space:]]*\([^)]*\)[[:space:]]*$//; s/[[:space:]]+$//')"
  [ -n "$new_path" ] && [ -e "$new_path" ] || continue
  if [ -d "$new_path" ]; then
    harness_hit="$(grep -rlE "$HARNESS_CDP_RE" "$new_path" 2>/dev/null | head -1)"
  elif [ -r "$new_path" ]; then
    harness_hit="$(grep -lE "$HARNESS_CDP_RE" "$new_path" 2>/dev/null)"
  else
    harness_hit=""
  fi
  if [ -n "$harness_hit" ]; then
    echo "warn: Built item ${new_path} drives a site through the browser harness; its home is browser-harness-js skills/cdp/learnings/<short-id>/ (a thin CLI may stay here), see the Distill homes table" >&2
    warns=$((warns + 1))
  fi
done <<< "$input"

# Step -1 coverage, the same three-state rule as `Built:` above. A seam that was never
# configured and a seam that was silently dropped read identically without this line, and the
# seam is where an operator's whole distill half lives: `wrap.before`/`wrap.after` name a
# skill this command runs, so a dropped step -1 loses that skill with no trace in the report.
if [ "$follow_report" = 1 ]; then
  : # the seams ran in the first report; a follow-through report owes no Seam line
elif ! printf '%s' "$input" | grep -q '\*\*Seam:\*\*'; then
  echo "line 0: no '**Seam:**' line; step -1 (the before/after seams) owes an outcome" >&2
  echo "  add one of: '**Seam:** <side> <skill> ran: <outcome>', '**Seam:** NOTHING: no seam configured', '**Seam:** SKIPPED: <why>'" >&2
  findings=$((findings + 1))
elif ! printf '%s' "$input" | grep -qE '\*\*Seam:\*\*[[:space:]]*(NOTHING|SKIPPED|[^[:space:]])'; then
  echo "line 0: '**Seam:**' is empty; name the side and skill that ran, or NOTHING, or SKIPPED with a reason" >&2
  findings=$((findings + 1))
fi

# FYI tags. The block used to mix four kinds of line under one header: a step that did not
# run, a state the operator meets next session, something that went wrong during the pass,
# and an ask wearing prose ("turning the knob on now works cleanly"). An operator told to
# "follow the FYI" then got nine ambiguous states and picked a reading. Each bullet now opens
# with its kind, the same way each `**Built:**` item opens with its verdict.
#
# SKIPPED  a step that did not run, and where its output went instead.
# STATE    a fact the operator meets next time: a knob value, a dirty checkout, a local file.
# INCIDENT something that went wrong during this pass and how it was resolved.
#
# The block is optional: no `**FYI:**` header, or a header with no bullets, is not a finding.
# `- NOTHING` is the sentinel the template already prints and carries no tag.

# Ask shapes. An FYI line carries no ask: a line telling the operator to do, decide, or
# consider something is a `Needs you` item with its own DECIDE/RUN/REVIEW/UNBLOCK tag. The
# words: should, consider, recommend, you can, turn(ing) <knob> on, works cleanly,
# worth a/an/the/doing/turning, next time run, please.
FYI_ASK_RE='\bshould\b|\bconsider\b|\brecommend|\byou can\b|\bturn(ing)? [a-z._]+ on\b|\bworks cleanly\b|\bworth (a|an|the|doing|turning)\b|\bnext time,? run\b|\bplease\b'

_f_state=0
_f_lineno=0
while IFS= read -r _f_line; do
  _f_lineno=$((_f_lineno + 1))
  if [ "$_f_state" = 0 ]; then
    case "$_f_line" in *'**FYI:**'*) _f_state=1 ;; esac
    continue
  fi
  # A blank line or the next bold header closes the block, same bound as the Built parser.
  case "$_f_line" in
    '- '*) : ;;
    *) break ;;
  esac
  _f_item="${_f_line#- }"
  case "$_f_item" in
    NOTHING*) continue ;;
  esac

  case "$_f_item" in
    'SKIPPED '*|'STATE '*|'INCIDENT '*) : ;;
    *)
      echo "line ${_f_lineno}: FYI bullet has no tag; open it with SKIPPED (a step that did not run), STATE (a fact the operator meets next time), or INCIDENT (something that went wrong this pass)" >&2
      echo "  - ${_f_item}" >&2
      findings=$((findings + 1))
      continue ;;
  esac

  _f_lower="$(printf '%s' "$_f_item" | tr '[:upper:]' '[:lower:]')"
  if printf '%s' "$_f_lower" | grep -qiE "$FYI_ASK_RE"; then
    echo "line ${_f_lineno}: that is an ask; move it to Needs you as DECIDE or RUN" >&2
    echo "  - ${_f_item}" >&2
    findings=$((findings + 1))
  fi
done <<< "$input"

if [ "$findings" -gt 0 ]; then
  echo "report-lint: ${findings} finding(s), ${warns} warn(s)" >&2
  exit 1
fi
echo "report-lint: clean (${warns} warn(s))"
exit 0
