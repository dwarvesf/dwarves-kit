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

# stat(1) is not portable: BSD wants -f %m, GNU wants -c %Y. Every age in this script goes
# through here so the split lives in exactly one place.
mtime_of() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null || echo 0; }

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

days_since() { echo $(( ( NOW - ${1:-0} ) / 86400 )); }

# A basename goes into a grep pattern, so every regex metacharacter in it has to stop being
# one. A file literally named `notes(1).md` would otherwise search for a capture group.
re_escape() { printf '%s' "$1" | sed 's/[.[\*^$()+?{}|\\]/\\&/g'; }

emit() { printf '%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4"; FINDINGS=$((FINDINGS + 1)); }

wants() { case ",$DETECTORS," in *",$1,"*) return 0 ;; *) return 1 ;; esac; }

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
  git log --format='COMMIT %ct' --name-only --diff-filter=AMR -- '*.md' '*.txt' 2>/dev/null \
    | awk '/^COMMIT /{ts=$2; next} NF && !(seen[$0]++){print ts"\t"$0}' > "$ages"

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
  local dirs d entry age base dup dupsha entrysha found
  dirs="${STAGING_DIRS:-_inbox inbox _staging}"
  for d in $dirs; do
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
        for dup in $(git ls-files -- "*/$base" "$base" 2>/dev/null); do
          case "$dup" in "$d"/*) continue ;; esac
          dupsha=$(sha_of "$dup")
          if [ -n "$entrysha" ] && [ "$entrysha" = "$dupsha" ]; then
            found="$dup"; break
          fi
          [ -z "$found" ] && found="~$dup"
        done
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
detect_misplaced_record() {
  local dirs d f scopes owner owners n n_owner total rel dest slug closing
  dirs="${CENTRAL_DIRS:-_meta docs/research docs/briefs}"
  for d in $dirs; do
    [ -d "$d" ] || continue

    # Mega-goals are folders, not files, and their completion marker is a closing commit,
    # not a status field (no repo in the estate writes one). A closed mega-goal is a record
    # and belongs with its owner; an open one is a live engine and belongs where it is.
    if [ -d "$d/megagoals" ]; then
      for slug in "$d"/megagoals/*/; do
        [ -d "$slug" ] || continue
        case "$(basename "$slug")" in _archive|archive) continue ;; esac
        closing=$(git log --format='%h %s' -- "$slug" 2>/dev/null \
          | grep -iE '\b(close|closed|closing|complete|completed|concluded)\b' | head -1)
        [ -n "$closing" ] || continue
        emit 3 UNSURE "${slug%/}" "closed mega-goal still in the control surface: \"$closing\"; a completed mega-goal is a record and co-locates with its owner; no commit scope resolves an owner, so the operator names the destination"
      done
    fi

    for f in $(git ls-files -- "$d" 2>/dev/null); do
      case "$f" in "$d"/megagoals/*) continue ;; esac
      printf '%s\n' "$f" | grep -qE '\.(md|txt)$' || continue
      # The control surface's OWN index and log files touch every tool in the repo by
      # design. Judging them by who touched them says "everyone", which is not an owner.
      printf '%s\n' "$f" | grep -qE "$CONTROL_SURFACE_RE" && continue

      total=$(git log --oneline -- "$f" 2>/dev/null | wc -l | tr -d ' ')
      [ "${total:-0}" -ge 1 ] || continue
      scopes=$(git log --format='%s' -- "$f" 2>/dev/null \
        | sed -n 's/^[a-z]\{2,\}(\([A-Za-z0-9._-]\{1,\}\)).*/\1/p')
      owners=$(printf '%s\n' "$scopes" | awk 'NF' | sort | uniq -c | sort -rn \
        | while read -r c s; do
            if [ -d "tools/$s" ]; then echo "$c tools/$s"
            elif [ -d "experiments/$s" ]; then echo "$c experiments/$s"; fi
          done)
      n=$(printf '%s\n' "$owners" | awk 'NF' | wc -l | tr -d ' ')
      [ "${n:-0}" -ge 1 ] || continue
      rel="${f#"$d"/}"

      # One owner wins only when it accounts for at least half the file's own commits.
      # A single stray commit under a tool's scope, in a file some other surface owns, is
      # a coincidence, and acting on it would move a record that was never that tool's.
      owner=$(printf '%s\n' "$owners" | head -1 | awk '{print $2}')
      n_owner=$(printf '%s\n' "$owners" | head -1 | awk '{print $1+0}')
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
    done
  done
}

# ------------------------------------------------------------------ detector 4
# An append-only log past the budget THE REPO ITSELF documents. A threshold this scanner
# invented would be an opinion; a threshold quoted from the repo's own prose is evidence.
detect_log_budget() {
  local globs g f total month_line month_max month_name src srcline nums total_t month_t quoted
  globs="${LOG_GLOBS:-*LAB_LOG.md *INGEST_LOG.md *learned-ledger.md}"
  for g in $globs; do
    for f in $(git ls-files -- "$g" "**/$g" 2>/dev/null | awk 'NF && !seen[$0]++'); do
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
      src=$(git grep -n -F -- "$(basename "$f" .md)" -- '*CLAUDE.md' '*README.md' 'docs/*.md' 2>/dev/null \
        | grep -E '[0-9]{3,5}[^0-9]{0,20}lines' | head -1)
      total_t=""; month_t=""
      if [ -n "$src" ]; then
        srcline="${src#*:*:}"
        nums=$(printf '%s' "$srcline" | grep -oE '[0-9]{3,5}' | sort -n | awk 'NF && !seen[$0]++')
        month_t=$(printf '%s\n' "$nums" | head -1)
        total_t=$(printf '%s\n' "$nums" | tail -1)
        [ "$month_t" = "$total_t" ] && month_t=""
        quoted="source ${src%%:*}:$(printf '%s' "$src" | cut -d: -f2) \"$(printf '%s' "$srcline" | sed 's/^[[:space:]]*//' | cut -c1-160)\""
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
    done
  done
}

# ------------------------------------------------------------------ detector 5
# A gitignored directory that is large and cold. REPORT ONLY, unconditionally: the scanner
# cannot see what a gitignored path is for, so proposing its deletion would be a guess with
# an irreversible cost attached.
detect_cold_ignored() {
  local d kb mb newest
  for d in $(git status --porcelain --ignored=matching 2>/dev/null | sed -n 's|^!! \(.*\)/$|\1|p'); do
    [ -d "$d" ] || continue
    kb=$(du -sk "$d" 2>/dev/null | awk '{print $1+0}')
    mb=$(( kb / 1024 ))
    [ "$mb" -ge "$COLD_MB" ] || continue
    find "$d" -type f -newermt "-${COLD_DAYS} days" -print -quit 2>/dev/null | grep -q . && continue
    newest=$(find "$d" -type f -newermt "-$(( COLD_DAYS * 4 )) days" -print -quit 2>/dev/null)
    emit 5 UNSURE "$d" "size ${mb}MB (threshold ${COLD_MB}MB), no file newer than ${COLD_DAYS}d$( [ -n "$newest" ] && echo ", newest within $(( COLD_DAYS * 4 ))d" ); REPORT ONLY, gitignored, never a deletion proposal"
  done
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

cd "$REPO" 2>/dev/null || die "cannot enter '$REPO'"
git rev-parse --show-toplevel >/dev/null 2>&1 || die "'$REPO' is not a git repo (the machine surface belongs to disk-reclaim, not here)"
cd "$(git rev-parse --show-toplevel)" || die "cannot enter the repo root"

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
