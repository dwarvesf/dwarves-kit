#!/usr/bin/env bash
# repohygiene.sh -- Tier 1 of the kit:repo-hygiene audit loop (docs/patterns/audit-loop.md).
#
# Enumerates files inside a git repo that have decayed, and emits one finding per line with
# the EVIDENCE that proves it inline. Detection is cheap; VERIFICATION is what costs, so a
# finding this scanner cannot back with a quoted command, a count against a threshold, or a
# path, is not emitted at all.
#
# It never writes to the target repo. The only mutation the audit loop ever applies is a
# `git mv` for a detector-3 finding, and the skill applies it, not this script.
#
# Detectors:
#   1 unreferenced-doc   a tracked non-code file older than --stale-days that nothing references
#   2 stale-inbox        a staging entry older than --inbox-days, plus its duplicate if one exists
#   3 misplaced-record   a record in a central dir whose owner is one tool or experiment
#   4 log-budget         an append-only log past the threshold the repo itself documents
#   5 cold-ignored-dir   a gitignored directory that is large and cold (REPORT ONLY, always)
#
# Output is TSV: <detector>\t<verdict>\t<path>\t<evidence>, then a SUMMARY line.
# Verdicts are the audit-loop grammar: FIX / REMOVE / UNSURE. OK items are not emitted.
#
# Usage:
#   repohygiene.sh scan [--repo DIR] [--detectors 1,2,3,4,5]
#                       [--stale-days N] [--inbox-days N] [--cold-days N] [--cold-mb N]
#                       [--max-candidates N]
#                       [--staging-dir D]... [--central-dir D]... [--log GLOB]...
#   repohygiene.sh detectors    -> the detector ids and what each one checks
#
# Exit: 0 always when the scan itself ran (findings are output, not failure); 2 on bad usage
# or a target that is not a git repo.

set -uo pipefail

STALE_DAYS=180
INBOX_DAYS=30
COLD_DAYS=90
COLD_MB=100
MAX_CANDIDATES=400
REPO="."
DETECTORS="1,2,3,4,5"
STAGING_DIRS=""
CENTRAL_DIRS=""
LOG_GLOBS=""

# Paths whose whole point is to be long-lived, append-only, or a dated record. Detector 1
# would flag every one of them, and every flag would be noise: a 2026-05 spec is unreferenced
# because it describes 2026-05, not because it decayed. Same exclusion discipline as
# skills/doc-drift/SKILL.md's dated-record carve-out.
CONTROL_SURFACE_RE='(^|/)(README|CLAUDE|AGENTS|WORKFLOW|CONTRIBUTING|CHANGELOG|MANUAL|LICENSE|SKILL|INDEX|MANIFEST|CONSUMERS|BACKLOG|ROADMAP|INVENTORY|LAB_LOG|OPERATE|SCHEMAS|FEATURES)\.(md|txt)$|(^|/)[A-Za-z0-9_-]*(INGEST_LOG|learned-ledger|backlog-staging|boards)\.(md|txt)$'
D1_EXCLUDE_RE="${CONTROL_SURFACE_RE}"'|(^|/)(specs|decisions|research|retro|retros|handoff|handoffs|absorption|incidents|verification|implementation-notes|adr|archive|lab-log-archive|megagoals|results|drafts|fixtures|samples|snapshots|node_modules|vendor)/|^\.github/'

usage() { sed -n '3,30p' "$0" | sed 's/^# \{0,1\}//'; }

die() { echo "repohygiene: $*" >&2; exit 2; }

# stat(1) is not portable: BSD wants -f %m, GNU wants -c %Y. Probe ONCE and remember which.
# Chaining the two forms with || is wrong, not merely ugly: GNU `stat -f` means
# --file-system, so it prints a seven-line filesystem report to stdout AND exits 1, and the
# fallback then appends the real mtime to that report. Every age on Linux came back as
# garbage, every arithmetic on it failed, and every detector-2 entry silently dropped out.
STAT_FMT=""
mtime_of() {
  if [ -z "$STAT_FMT" ]; then
    if stat -c %Y . >/dev/null 2>&1; then STAT_FMT="gnu"; else STAT_FMT="bsd"; fi
  fi
  if [ "$STAT_FMT" = "gnu" ]; then stat -c %Y "$1" 2>/dev/null || echo 0
  else stat -f %m "$1" 2>/dev/null || echo 0; fi
}

sha_of() {
  if command -v shasum >/dev/null 2>&1; then shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'
  else sha256sum "$1" 2>/dev/null | awk '{print $1}'; fi
}

# A staging DROP is often a folder, and the folder's own mtime only tracks its direct
# children, so a year-old drop touched by one recent nested write must not read as fresh.
newest_mtime() {
  if [ -d "$1" ]; then
    find "$1" -type f 2>/dev/null | while read -r _f; do mtime_of "$_f"; done \
      | sort -rn | head -1 | grep . || mtime_of "$1"
  else
    mtime_of "$1"
  fi
}

# Fail CLOSED. A non-numeric timestamp used to kill the arithmetic, leave `age` empty, and
# make the `[ "$age" -gt N ] || continue` guard skip the item, so a poisoned input read as
# "young enough, nothing to see". An unreadable age now returns -1, which is older than any
# threshold, so the item stays in the set and gets looked at.
days_since() {
  case "${1:-}" in
    ''|*[!0-9]*) echo -1; return ;;
  esac
  echo $(( ( NOW - $1 ) / 86400 ))
}

# A basename goes into a grep pattern, so every regex metacharacter in it has to stop being
# one. A file literally named `notes(1).md` would otherwise search for a capture group.
re_escape() { printf '%s' "$1" | sed 's/[].[\*^$()+?{}|\\]/\\&/g'; }

# The output is TSV and its fields carry repo-controlled text: a filename, a commit subject,
# a quoted line from a repo doc. A newline in a staging filename used to forge an ENTIRE
# extra row, and a detector-3 FIX row is the one verdict the loop acts on, so a forged row
# chose the `git mv` source and destination. A tab forged a column. Both die here, once, for
# every call site.
scrub() { printf '%s' "$1" | tr '\t\n\r' '   '; }

emit() { printf '%s\t%s\t%s\t%s\n' "$(scrub "$1")" "$(scrub "$2")" "$(scrub "$3")" "$(scrub "$4")"; FINDINGS=$((FINDINGS + 1)); }

wants() { case ",$DETECTORS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

# The skill promises this loop is REPO-SCOPED. Without this, `--staging-dir ~/.ssh` put
# private-key filenames and a hash prefix of each key into a report meant for a PR body.
# Every operator-supplied directory resolves and must land under the repo root.
inside_repo() {
  local abs
  abs=$(cd "$1" 2>/dev/null && pwd -P) || return 1
  case "$abs/" in
    "$REPO_ROOT"/*) return 0 ;;
    "$REPO_ROOT"/) return 0 ;;
    *) echo "repohygiene: refusing '$1', it resolves outside the repo root; this loop is repo-scoped and the machine surface belongs to disk-reclaim" >&2; return 1 ;;
  esac
}

# ------------------------------------------------------------------ detector 1
# A tracked non-code file, older than the threshold, that no other tracked file references.
#
# Ages come from ONE batched `git log --name-only` pass, never one subprocess per file: the
# per-file form is what makes an audit's cost scale with repo size instead of with drift.
# The reference grep stays per-candidate on purpose, because that grep IS the evidence: a
# batched alternation would prove the set unreferenced without proving any single member so.
detect_unreferenced() {
  local ages candidates path ts age esc hits cmd
  ages="$TMP/ages"
  # The header is found STRUCTURALLY, by the blank line git always puts after it, never by a
  # text prefix. A prefix is forgeable: a tracked path named `COMMIT 9999999999` parsed as a
  # header and poisoned the timestamp of the file listed after it, which then failed the
  # arithmetic and dropped a real candidate out of the set. A path is never blank and is
  # never followed by a blank line here, so the one-line lookbehind below cannot be spoofed.
  # `core.quotePath=false` keeps a Vietnamese filename from arriving C-quoted, which used to
  # drop every non-ASCII path out of detectors 1, 3, and 4 without a word.
  git -c core.quotePath=false log --format='%ct' --name-only --diff-filter=AMR \
    -- '*.md' '*.txt' 2>/dev/null \
    | awk '/^$/ { ts = prev; prev = ""; next }
           { if (prev != "" && !(seen[prev]++)) print ts "\t" prev; prev = $0 }
           END { if (prev != "" && !(seen[prev]++)) print ts "\t" prev }' > "$ages"

  candidates="$TMP/d1-candidates"
  : > "$candidates"
  while IFS=$'\t' read -r ts path; do
    [ -n "${path:-}" ] || continue
    [ -f "$path" ] || continue
    printf '%s\n' "$path" | grep -qE "$D1_EXCLUDE_RE" && continue
    age=$(days_since "$ts")
    [ "$age" -gt "$STALE_DAYS" ] || continue
    printf '%s\t%s\t%s\n' "$path" "$ts" "$age" >> "$candidates"
  done < "$ages"

  # The reference grep is the expensive half, one pass per candidate. A threshold set low
  # enough to admit thousands of candidates turns a bounded audit into a multi-minute scan,
  # so the oldest MAX_CANDIDATES are judged and the overflow is reported, never dropped
  # silently. Raising --stale-days is the fix; raising the cap is the workaround.
  local total_cand
  total_cand=$(wc -l < "$candidates" | tr -d ' ')
  if [ "$total_cand" -gt "$MAX_CANDIDATES" ]; then
    sort -t$'\t' -k2,2n "$candidates" -o "$candidates"
    emit 1 UNSURE "(candidate set)" "$total_cand files past ${STALE_DAYS}d, over the ${MAX_CANDIDATES} cap; the ${MAX_CANDIDATES} oldest were judged; raise --stale-days to narrow the set or --max-candidates to widen the pass"
    head -"$MAX_CANDIDATES" "$candidates" > "$candidates.capped" && mv "$candidates.capped" "$candidates"
  fi

  while IFS=$'\t' read -r path ts age; do
    [ -n "${path:-}" ] || continue
    esc=$(re_escape "$(basename "$path")")
    cmd="git grep -I -n -E '(^|[^A-Za-z0-9_-])$esc' -- ':(exclude)$path'"
    hits=$(git grep -I -n -E "(^|[^A-Za-z0-9_-])$esc" -- ":(exclude)$path" 2>/dev/null | wc -l | tr -d ' ')
    [ "$hits" = "0" ] || continue
    emit 1 UNSURE "$path" "last touched $(date -r "$ts" +%Y-%m-%d 2>/dev/null || echo unknown) (${age}d, threshold ${STALE_DAYS}d); $cmd -> 0 hits outside itself"
  done < "$candidates"
}

# ------------------------------------------------------------------ detector 2
# A staging entry older than the threshold. Staging dirs are usually gitignored, so age comes
# from the filesystem, not from git, and a duplicate is proven by content hash, not by name.
detect_stale_inbox() {
  local dirs d entry age base dup dupsha entrysha found tracked
  dirs="${STAGING_DIRS:-_inbox inbox _staging}"
  tracked="$TMP/tracked"
  git -c core.quotePath=false ls-files -z 2>/dev/null > "$tracked"
  for d in $dirs; do
    inside_repo "$d" || continue
    [ -d "$d" ] || continue
    for entry in "$d"/* "$d"/.[!.]*; do
      [ -e "$entry" ] || continue
      base=$(basename "$entry")
      case "$base" in README.md|.gitignore|.gitkeep) continue ;; esac
      age=$(days_since "$(newest_mtime "$entry")")
      [ "$age" -gt "$INBOX_DAYS" ] || continue

      found=""
      if [ -f "$entry" ]; then
        entrysha=$(sha_of "$entry")
        # The basename is compared in the shell, never handed to git as a pathspec: a file
        # literally named `*` used to match every tracked file and the first hit was
        # reported as its "same-name copy", which is forged evidence.
        while IFS= read -r -d '' dup; do
          [ "$(basename "$dup")" = "$base" ] || continue
          case "$dup" in "$d"/*) continue ;; esac
          dupsha=$(sha_of "$dup")
          if [ -n "$entrysha" ] && [ "$entrysha" = "$dupsha" ]; then
            found="$dup"; break
          fi
          [ -z "$found" ] && found="~$dup"
        done < "$tracked"
      fi

      if [ -n "$found" ] && [ "${found#\~}" = "$found" ]; then
        emit 2 REMOVE "$entry" "age ${age}d (threshold ${INBOX_DAYS}d); duplicate-of $found (identical sha256 ${entrysha:0:12}); report only, the operator routes or trashes"
      elif [ -n "$found" ]; then
        emit 2 UNSURE "$entry" "age ${age}d (threshold ${INBOX_DAYS}d); same-name copy at ${found#\~} but content differs; route or trash is the operator's call"
      else
        emit 2 UNSURE "$entry" "age ${age}d (threshold ${INBOX_DAYS}d); no duplicate found in the repo; route or trash is the operator's call"
      fi
    done
  done
}

# ------------------------------------------------------------------ detector 3
# A record parked in a central directory whose real owner is one tool or experiment.
#
# The owner comes from the CONVENTIONAL-COMMIT SCOPE of the commits that touched the file,
# resolved against a live tools/<scope>/ or experiments/<scope>/ dir. Content heuristics were
# tried first and are too noisy: a research note names every tool it surveyed, so a file whose
# owner is vps-mon mentions four other tools too. What a file's own history says about who
# wrote it does not have that problem.

# The owner of a path, by the conventional-commit scope of the commits that touched it. Prints
# "<count> <owner>" per resolved owner, most-owning first, and nothing when none resolves.
#
# A scope must start alphanumeric and carry no `..` segment. `feat(..): x` otherwise resolved
# as the owner `tools/..` and produced a FIX row whose destination traversed out of the tool
# directory, on the one verdict the loop actually acts on.
#
# The path arrives as `:(literal)`, because a git pathspec has WILDCARD MAGIC ON BY DEFAULT and
# the path is repo-controlled. A directory literally named `*` otherwise matched every sibling's
# history, so a one-commit folder harvested a live goal's owner and its commit majority, and
# both landed in a FIX row.
scope_owners() {
  git log --format='%s' -- ":(literal)$1" 2>/dev/null \
    | sed -n 's/^[a-z]\{2,\}(\([A-Za-z0-9][A-Za-z0-9._-]*\)).*/\1/p' \
    | grep -v '\.\.' | awk 'NF' | sort | uniq -c | sort -rn \
    | while read -r c s; do
        if [ -d "tools/$s" ]; then echo "$c tools/$s"
        elif [ -d "experiments/$s" ]; then echo "$c experiments/$s"; fi
      done
}

# The single owner of a path plus the numbers that justify it, as
# "<owners resolved>\t<top owner>\t<its commits>\t<total commits>". Both detector-3 branches
# decide with the same majority rule, so they read it from one place.
resolve_owner() {
  local owners
  owners=$(scope_owners "$1")
  printf '%s\t%s\t%s\t%s\n' \
    "$(printf '%s\n' "$owners" | awk 'NF' | wc -l | tr -d ' ')" \
    "$(printf '%s\n' "$owners" | head -1 | awk '{print $2}')" \
    "$(printf '%s\n' "$owners" | head -1 | awk '{print $1+0}')" \
    "$(git log --oneline -- ":(literal)$1" 2>/dev/null | wc -l | tr -d ' ')"
}

# Whether a mega-goal folder DECLARES itself finished, read from the folder's own top-level
# docs. Prints "<closed|open|unmarked>\t<file>:<line>".
#
# A declaration is a `Status:` or `State:` heading, bold label, or list item at the start of a
# line, which is the shape the estate writes ("## Status 2026-09-01: all four goals SHIPPED",
# "**Status:** charter only"). A bare `## Status` heading declares nothing and is not a marker.
# Sub-goal files under goals/ carry their own per-sub-goal status lines and are excluded: one
# drafted sub-goal does not describe the goal. An open marker anywhere WINS over a closed one,
# because the loop's only mutation is a move and a live engine must not be moved out of the
# control surface.
#
# The keyword test runs on the line's TEXT, never on its path: a mega-goal literally named
# `safari-net-complete` would otherwise declare itself complete through its own directory name.
#
# Only the marker's `file:line` ever reaches a finding, never the line itself. The line is
# repo-controlled free text, and a FIX row's evidence is what an agent parses the `git mv`
# destination out of: a status line reading `co-locate to ../../../tmp/pwned` put a SECOND
# destination in front of the real one, and a status line carrying a deletion verb put that verb
# into a finding, which invariant 1 forbids outright.
MG_CLOSED_RE='(closed|close-out|closeout|complete|completed|done|shipped|archived|dropped|superseded|retired|abandoned)'
MG_OPEN_RE='(charter|draft|queued|active|live|in progress|in-progress|wip|held|blocked|pending|open|scaffolded|deferred|planned|ready|not started)'
MG_DECL_RE='^([[:space:]]*[-*][[:space:]]+|#{1,6}[[:space:]]*)?[[:space:]]*\**(Status|State)\**[[:space:]]*[:[:space:]]'

# The files that can carry a mega-goal's record. `$2` of 1 reads the folder's own top level
# only, which is what keeps a per-sub-goal `Status:` line under goals/ from describing the goal.
#
# The extension set is wider than the `.md` the estate writes, and the match is
# case-insensitive, because the completion gate must not be dodged by renaming one file: a
# checklist in `ROADMAP.txt` was invisible to the box count, and the folder above it then read
# as finished with "none open".
#
# `-type f` is load-bearing, not tidiness: it excludes SYMLINKS. A tracked
# `STATUS.md -> /outside/secret` otherwise decided a folder's verdict and put matching lines
# from outside the repo into a report bound for a PR body, the same escape invariant 13 exists
# for on the `--staging-dir` side.
mg_docs() {
  local depth=""
  [ "${2:-0}" = "1" ] && depth="-maxdepth 1"
  find "$1" $depth -type f \
    \( -iname '*.md' -o -iname '*.markdown' -o -iname '*.mdx' -o -iname '*.txt' \) \
    -print0 2>/dev/null
}

mg_state() {
  local f rec n lower first_closed=""
  while IFS= read -r -d '' f; do
    while IFS= read -r rec; do
      n="${rec%%:*}"
      lower=$(printf '%s' "${rec#*:}" | tr 'A-Z' 'a-z')
      if printf '%s\n' "$lower" | grep -qE "(^|[^a-z])${MG_OPEN_RE}([^a-z]|\$)"; then
        printf 'open\t%s:%s\n' "$f" "$n"; return 0
      fi
      if [ -z "$first_closed" ] \
         && printf '%s\n' "$lower" | grep -qE "(^|[^a-z])${MG_CLOSED_RE}([^a-z]|\$)"; then
        first_closed="$f:$n"
      fi
    done < <(grep -nE "$MG_DECL_RE" "$f" 2>/dev/null)
  done < <(mg_docs "$1" 1)
  [ -n "$first_closed" ] && { printf 'closed\t%s\n' "$first_closed"; return 0; }
  printf 'unmarked\t\n'
}

# Every checkbox anywhere in a mega-goal folder, one `<file>:<line>` per line. `unchecked`
# counts `- [ ]` and the `- [~]` in-progress form the estate writes; `checked` counts `- [x]`.
#
# A box counts only where a checklist actually puts one: at the start of a line, of a
# blockquote, or of a table cell, on a bullet OR a number. That anchor is what keeps PROSE
# ABOUT checkboxes out of the count, since every POINTER_PROMPT.md in the estate spells the
# convention out mid-sentence as `- [ ] NN-... PR #N`. The numbered and blockquoted forms count
# because sub-goals in this estate are numbered, and missing one reads as "none open", which
# fails in the direction that MOVES something.
#
# The path prefix is written by the shell, never by `awk -v`: awk REJECTS a newline in a `-v`
# value, exits 2, and prints nothing, so a mega-goal directory with a newline in its name
# emitted zero boxes and the gate above read the folder as finished. Only the `file:line` is
# returned, never the line, so no repo-controlled prose reaches a finding.
mg_boxes() {
  local f line
  while IFS= read -r -d '' f; do
    while IFS= read -r line; do
      printf '%s:%s\n' "$f" "${line%%:*}"
    done < <(grep -nE "(^|\|)[[:space:]>]*([0-9]+[.)]|[-*])[[:space:]]*\[[$2]\]" "$f" 2>/dev/null)
  done < <(mg_docs "$1" 0)
}

detect_misplaced_record() {
  local dirs d f owner owners n n_owner total rel dest slug closing base
  local state marker unchecked n_un n_ok first_un hold
  dirs="${CENTRAL_DIRS:-_meta docs/research docs/briefs}"
  for d in $dirs; do
    inside_repo "$d" || continue
    [ -d "$d" ] || continue

    # Mega-goals are folders, not files. A closed one is a record and belongs with its owner;
    # an open one is a live engine and belongs where it is.
    #
    # The completion test reads the folder's OWN state first, in a fixed precedence, because
    # commit keywords alone were the first test and misfired on three of five real folders: a
    # sweep commit reading "co-locate completed mega-goals" carried a keyword about OTHER
    # goals, and "mochi build complete, 08 shipped" closed nothing while the folder's ROADMAP
    # still carried four open sub-goals and a "Blocked on Han" section.
    #
    #   0. a folder with no tracked record in it is residue, not a mega-goal, and is skipped
    #   1. an explicit status marker in the folder outranks everything (mg_state)
    #   2. an unchecked checklist item anywhere means NOT complete, whatever the log says
    #   3. only a folder that declares nothing at all falls back to commit evidence, and that
    #      can never do better than UNSURE
    #
    # A commit subject alone never produces a FIX for a mega-goal folder.
    if [ -d "$d/megagoals" ]; then
      for slug in "$d"/megagoals/*/; do
        [ -d "$slug" ] || continue
        base=$(basename "$slug")
        case "$base" in _archive|archive) continue ;; esac
        slug="${slug%/}"
        # A folder holding no TRACKED record is residue, not a mega-goal: `git mv` leaves the
        # source directory behind whenever untracked scratch sits inside it, and judging that
        # empty shell by the very commit that emptied it reported the move as still pending.
        # `:(literal)` because the path is repo-controlled and a pathspec globs by default.
        git -c core.quotePath=false ls-files -z -- ":(literal)$slug" 2>/dev/null \
          | tr '\0' '\n' | grep -qiE '\.(md|markdown|mdx|txt)$' || continue

        state=$(mg_state "$slug")
        marker="${state#*	}"; state="${state%%	*}"
        [ "$state" = "open" ] && continue

        unchecked=$(mg_boxes "$slug" '[:space:]~-')
        n_un=$(printf '%s' "$unchecked" | grep -c .)
        n_ok=$(mg_boxes "$slug" 'xX' | grep -c .)
        first_un=$(printf '%s\n' "$unchecked" | head -1)

        if [ "$n_un" -gt 0 ]; then
          # Its own record says unfinished. A closed marker on top of open boxes is a folder
          # contradicting itself, which is the operator's call, not a move.
          [ "$state" = "closed" ] && emit 3 UNSURE "$slug" \
            "a status marker at $marker says closed, but $n_un checklist items are still open, first at $first_un; the folder contradicts itself, so nothing moves until the operator resolves which is true"
          continue
        fi

        if [ "$state" = "closed" ]; then
          IFS='	' read -r n owner n_owner total < <(resolve_owner "$slug")
          # Everything that must hold before a move is proposed, each with the reason it did
          # not. A FIX needs POSITIVE completion evidence, not merely the absence of an open
          # box: zero checked items is also what every fail-open path produces, so a folder
          # whose checklist could not be read cannot reach FIX through that hole.
          hold=""
          case "$base" in
            *[][*?]*) hold="its directory name carries a glob metacharacter, which would steer both the pathspec that resolves its owner and the move itself" ;;
          esac
          if [ -z "$hold" ] && [ "${n_ok:-0}" -eq 0 ]; then
            hold="the folder carries no checked checklist item either, so nothing in it positively records a finished sub-goal"
          fi
          if [ -z "$hold" ] && [ "${n:-0}" != "1" ]; then
            hold="$n commit scopes resolve an owner ($(scope_owners "$slug" | awk '{printf "%s x%s ", $2, $1}')), so no single one names the destination"
          fi
          if [ -z "$hold" ] && [ $(( n_owner * 2 )) -lt "${total:-0}" ]; then
            hold="its only owner scope $owner accounts for $n_owner of the $total commits touching it, short of the majority a move needs"
          fi
          if [ -z "$hold" ]; then
            case "$d" in
              _meta) dest="$owner/docs/megagoals/$base/" ;;
              docs/*) dest="$owner/docs/${d#docs/}/megagoals/$base/" ;;
              *) dest="$owner/docs/$d/megagoals/$base/" ;;
            esac
            emit 3 FIX "$slug" "closed mega-goal still in the control surface: its own marker at $marker, $n_ok checklist items checked and none open; owner $owner in $n_owner of $total commits touching it, by conventional-commit scope; co-locate to $dest"
          else
            emit 3 UNSURE "$slug" "closed mega-goal still in the control surface: its own marker at $marker, $n_ok checklist items checked and none open; no move is proposed because $hold; the operator names the destination"
          fi
          continue
        fi

        # Unmarked and with nothing open. The folder says nothing about itself, so commit
        # evidence is all there is, and commit evidence is never enough to move anything.
        closing=$(git log --format='%h %s' -- ":(literal)$slug" 2>/dev/null \
          | grep -iE '\b(close|closed|closing|complete|completed|concluded)\b' | head -1)
        [ -n "$closing" ] || continue
        emit 3 UNSURE "$slug" "possibly-closed mega-goal in the control surface: the folder declares no status and has $n_ok checked items and none open, so the only evidence is a commit subject, \"$closing\"; a commit keyword is not a closure record, so the operator confirms before anything moves"
      done
    fi

    # NUL-delimited, quoting disabled: an unquoted `$(git ls-files)` word-split a path with a
    # space into two nonexistent paths and dropped it, and C-quoting hid every non-ASCII one.
    while IFS= read -r -d '' f; do
      case "$f" in "$d"/megagoals/*) continue ;; esac
      printf '%s\n' "$f" | grep -qE '\.(md|txt)$' || continue
      # The control surface's OWN index and log files touch every tool in the repo by
      # design. Judging them by who touched them says "everyone", which is not an owner.
      printf '%s\n' "$f" | grep -qE "$CONTROL_SURFACE_RE" && continue

      # One owner wins only when it accounts for at least half the file's own commits, so a
      # minority scope in a file some other surface owns cannot claim it. A file with ONE
      # commit still yields a FIX, deliberately: that is exactly the fixed-central-path case
      # this detector was built for, where a single agent run wrote the file and moved on.
      IFS='	' read -r n owner n_owner total < <(resolve_owner "$f")
      [ "${total:-0}" -ge 1 ] || continue
      [ "${n:-0}" -ge 1 ] || continue
      owners=$(scope_owners "$f")
      rel="${f#"$d"/}"

      if [ "$n" = "1" ] && [ $(( n_owner * 2 )) -ge "$total" ]; then
        case "$d" in
          _meta) dest="$owner/docs/$rel" ;;
          docs/*) dest="$owner/docs/${d#docs/}/$rel" ;;
          *) dest="$owner/docs/$d/$rel" ;;
        esac
        emit 3 FIX "$f" "owner $owner in $n_owner of $total commits touching it, by conventional-commit scope; latest: $(git log --format='%h %s' -1 -- "$f" 2>/dev/null); co-locate to $dest"
      elif [ "$n" -ge 2 ] && [ "$n" -le 3 ]; then
        emit 3 UNSURE "$f" "a central path reused across runs: $total commits, $n owners by commit scope ($(printf '%s\n' "$owners" | awk '{printf "%s x%s ", $2, $1}')); the operator splits it or names one owner"
      fi
    done < <(git -c core.quotePath=false ls-files -z -- "$d" 2>/dev/null)
  done
}

# ------------------------------------------------------------------ detector 4
# An append-only log past the budget THE REPO ITSELF documents. A threshold this scanner
# invented would be an opinion; a threshold quoted from the repo's own prose is evidence.
detect_log_budget() {
  local globs g f total month_line month_max month_name srcs src srcline nums total_t month_t quoted nsrc
  globs="${LOG_GLOBS:-*LAB_LOG.md *INGEST_LOG.md *learned-ledger.md}"
  for g in $globs; do
    while IFS= read -r -d '' f; do
      [ -f "$f" ] || continue
      total=$(wc -l < "$f" | tr -d ' ')
      # One month per LINE, not per occurrence: a log line that quotes three dates is still
      # one entry, and counting occurrences reported more entries than the file has lines.
      month_line=$(awk 'match($0, /[0-9]{4}-[0-9]{2}/) {print substr($0, RSTART, 7)}' "$f" \
        | sort | uniq -c | sort -rn | head -1)
      month_max=$(printf '%s' "$month_line" | awk '{print $1+0}')
      month_name=$(printf '%s' "$month_line" | awk '{print $2}')

      # The threshold's source: a line in the repo's own docs that names this log and carries
      # line counts. Largest number on that line is the whole-file budget, smallest the
      # per-month one, which is the shape every repo in the estate happens to write.
      #
      # Every matching line counts, not `head -1`. Taking the first hit in git's path order
      # let anyone suppress a real finding by adding a doc that sorts earlier and claims a
      # 99999-line budget, and the scan then reported CLEAN. The STRICTEST budget wins, and
      # disagreeing sources make the finding UNSURE rather than picking one.
      srcs=$(git -c core.quotePath=false grep -n -F -- "$(basename "$f" .md)" \
        -- 'CLAUDE.md' 'README.md' 'docs/*.md' '*/CLAUDE.md' '*/README.md' 2>/dev/null \
        | grep -E '[0-9]{3,5}[^0-9]{0,20}lines')
      total_t=""; month_t=""; quoted=""; nsrc=0
      if [ -n "$srcs" ]; then
        nsrc=$(printf '%s\n' "$srcs" | wc -l | tr -d ' ')
        # Strictest budget across all sources: the smallest whole-file number any of them
        # states, and the smallest per-month number any of them states.
        total_t=$(printf '%s\n' "$srcs" | while IFS= read -r s; do
                    printf '%s' "${s#*:*:}" | grep -oE '[0-9]{3,5}' | sort -n | tail -1
                  done | sort -n | head -1)
        month_t=$(printf '%s\n' "$srcs" | while IFS= read -r s; do
                    printf '%s' "${s#*:*:}" | grep -oE '[0-9]{3,5}' | sort -n | head -1
                  done | sort -n | head -1)
        [ "$month_t" = "$total_t" ] && month_t=""
        src=$(printf '%s\n' "$srcs" | head -1)
        srcline="${src#*:*:}"
        quoted="source ${src%%:*}:$(printf '%s' "$src" | cut -d: -f2) \"$(printf '%s' "$srcline" | sed 's/^[[:space:]]*//' | cut -c1-160)\""
        [ "$nsrc" -gt 1 ] && quoted="$quoted (strictest of $nsrc sources stating a budget)"
      fi

      if [ -z "$total_t" ]; then
        emit 4 UNSURE "$f" "total=${total} lines, busiest month ${month_name:-none} at ${month_max:-0}; no documented threshold found in this repo, so there is nothing to judge against"
        continue
      fi
      if [ "$total" -gt "$total_t" ]; then
        emit 4 FIX "$f" "total=${total} lines vs threshold ${total_t}; busiest month ${month_name} at ${month_max}${month_t:+ vs per-month ${month_t}}; ${quoted}; rotate or compact per the repo's own procedure, report only"
      elif [ -n "$month_t" ] && [ "${month_max:-0}" -gt "$month_t" ]; then
        emit 4 FIX "$f" "total=${total} lines within threshold ${total_t}, but month ${month_name} at ${month_max} vs per-month ${month_t}; ${quoted}; rotate or compact per the repo's own procedure, report only"
      fi
    done < <(git -c core.quotePath=false ls-files -z -- "$g" "**/$g" 2>/dev/null)
  done
}

# ------------------------------------------------------------------ detector 5
# A gitignored directory that is large and cold. REPORT ONLY, unconditionally: the scanner
# cannot see what a gitignored path is for, so proposing its deletion would be a guess with
# an irreversible cost attached.
detect_cold_ignored() {
  local d kb mb newest warm rc
  while IFS= read -r -d '' d; do
    d="${d%/}"
    [ -d "$d" ] || continue
    kb=$(du -sk "$d" 2>/dev/null | awk '{print $1+0}')
    mb=$(( kb / 1024 ))
    [ "$mb" -ge "$COLD_MB" ] || continue
    # find's EXIT STATUS decides, not its output. A rejected -newermt argument printed
    # nothing and exited non-zero, which read as "cold" and produced a coldness claim the
    # scan never actually verified.
    warm=$(find "$d" -type f -newermt "-${COLD_DAYS} days" -print -quit 2>/dev/null); rc=$?
    [ "$rc" -eq 0 ] || { emit 5 UNSURE "$d" "size ${mb}MB (threshold ${COLD_MB}MB); could not test coldness, find exited $rc for -newermt '-${COLD_DAYS} days'; REPORT ONLY, gitignored, never a deletion proposal"; continue; }
    [ -n "$warm" ] && continue
    newest=$(find "$d" -type f -newermt "-$(( COLD_DAYS * 4 )) days" -print -quit 2>/dev/null)
    emit 5 UNSURE "$d" "size ${mb}MB (threshold ${COLD_MB}MB), no file newer than ${COLD_DAYS}d$( [ -n "$newest" ] && echo ", newest within $(( COLD_DAYS * 4 ))d" ); REPORT ONLY, gitignored, never a deletion proposal"
  done < <(git status --porcelain -z --ignored=matching 2>/dev/null | tr '\0' '\n' | sed -n 's|^!! \(.*/\)$|\1|p' | tr '\n' '\0')
}

# ------------------------------------------------------------------ main
[ $# -ge 1 ] || { usage; exit 2; }
CMD="$1"; shift

case "$CMD" in
  detectors)
    printf '%s\n' \
      "1 unreferenced-doc   a tracked non-code file older than --stale-days that nothing references" \
      "2 stale-inbox        a staging entry older than --inbox-days, plus its duplicate if one exists" \
      "3 misplaced-record   a record in a central dir whose owner is one tool or experiment" \
      "4 log-budget         an append-only log past the threshold the repo itself documents" \
      "5 cold-ignored-dir   a gitignored directory that is large and cold (REPORT ONLY, always)"
    exit 0 ;;
  -h|--help|help) usage; exit 0 ;;
  scan) : ;;
  *) die "unknown command '$CMD' (try: scan, detectors)" ;;
esac

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 ;;
    --detectors) DETECTORS="${2:-}"; shift 2 ;;
    --stale-days) STALE_DAYS="${2:-}"; shift 2 ;;
    --inbox-days) INBOX_DAYS="${2:-}"; shift 2 ;;
    --cold-days) COLD_DAYS="${2:-}"; shift 2 ;;
    --cold-mb) COLD_MB="${2:-}"; shift 2 ;;
    --max-candidates) MAX_CANDIDATES="${2:-}"; shift 2 ;;
    --staging-dir) STAGING_DIRS="$STAGING_DIRS ${2:-}"; shift 2 ;;
    --central-dir) CENTRAL_DIRS="$CENTRAL_DIRS ${2:-}"; shift 2 ;;
    --log) LOG_GLOBS="$LOG_GLOBS ${2:-}"; shift 2 ;;
    *) die "unknown option '$1'" ;;
  esac
done

# Every numeric flag is validated before any arithmetic sees it. An unvalidated one used to
# reach `$(( COLD_DAYS * 4 ))`, where bash evaluates command substitution inside an array
# subscript, and reached `find -newermt` where a rejected argument read as a passing verdict.
for _pair in "STALE_DAYS=$STALE_DAYS" "INBOX_DAYS=$INBOX_DAYS" "COLD_DAYS=$COLD_DAYS" \
             "COLD_MB=$COLD_MB" "MAX_CANDIDATES=$MAX_CANDIDATES"; do
  case "${_pair#*=}" in
    ''|*[!0-9]*) die "${_pair%%=*} must be a non-negative integer (got '${_pair#*=}')" ;;
  esac
done
case "$DETECTORS" in
  ''|*[!1-5,]*) die "--detectors takes a comma-separated list of 1..5 (got '$DETECTORS')" ;;
esac

cd "$REPO" 2>/dev/null || die "cannot enter '$REPO'"
git rev-parse --show-toplevel >/dev/null 2>&1 || die "'$REPO' is not a git repo (the machine surface belongs to disk-reclaim, not here)"
REPO_ROOT=$(git rev-parse --show-toplevel)
cd "$REPO_ROOT" || die "cannot enter the repo root"
REPO_ROOT=$(pwd -P)

NOW=$(date +%s)
FINDINGS=0
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

printf 'detector\tverdict\tpath\tevidence\n'
wants 1 && detect_unreferenced
wants 2 && detect_stale_inbox
wants 3 && detect_misplaced_record
wants 4 && detect_log_budget
wants 5 && detect_cold_ignored
printf 'SUMMARY\t%s findings\t%s\tdetectors %s\n' "$FINDINGS" "$(pwd)" "$DETECTORS"
exit 0
