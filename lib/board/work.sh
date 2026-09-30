#!/usr/bin/env bash
# work.sh -- `board work`: one table of who is on what, how far along, and who is stuck.
#
# Joins five sources at call time and stores nothing: the board rows (parse-board.sh), the
# mega sub-goal files, git (branches and worktrees), `orca worktree ps` (terminal state) and
# the run ledger (rung reached). Read-only: no ledger write, no board flip, no orca verb other
# than `worktree ps`, no network. It sources only lib/telemetry/kit-log-dir.sh (pure on load)
# and re-implements the one-line `runid`, because gate-ledger.sh and ledger.sh copy files on
# load (kit_migrate_log_dir); tests/test-board-work.sh pins the copy against the real one.
#
# Usage: work.sh [--json] [--idle-min N] [--code-root D] [--megagoals-root D] [--now EPOCH]
#                [--backlog-file F] [--repo-root D]
#   --json           the schema-1 contract (see docs/specs/SPEC-366-execution-view.md)
#   --idle-min N     PARKED threshold in minutes (default 20)
#   --code-root D    repo whose branches and worktrees a mega's sub-goals point at
#   --megagoals-root D  overrides <repo-root>/_meta/megagoals
#   --now EPOCH      fixes the clock (test seam)
# Env: ORCA_BIN (default orca), GIT_BIN (default git).
# Exit: 0 after any render (orca absent included), 64 bad flag, 1 unreadable backlog.
#
# One function per source (src_board, src_mega, src_git, src_orca, src_ledger) writes
# normalized JSON under a temp dir; the join and the renderers read only those files.

set -uo pipefail

WORK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_ROOT="$(cd "$WORK_DIR/.." && pwd)"
ORCA_BIN="${ORCA_BIN:-orca}"
GIT_BIN="${GIT_BIN:-git}"

# shellcheck source=lib/telemetry/kit-log-dir.sh
source "$LIB_ROOT/telemetry/kit-log-dir.sh" || { echo "board work: lib/telemetry/kit-log-dir.sh missing or unreadable" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "board work: jq is required" >&2; exit 1; }

# Same rule as gate-ledger.sh runid(); runid_lines is the same chain over a stream of lines.
runid() { printf '%s' "$1" | tr '/ ' '--' | tr -cd '[:alnum:]._-'; }
runid_lines() { tr '/ ' '--' | tr -cd '[:alnum:]._-\n'; }
canon() { local d; if d="$(cd "$1" 2>/dev/null && pwd -P)"; then printf '%s' "$d"; else printf '%s' "$1"; fi; }
usage() { sed -n '2,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }
bad() { echo "board work: $1" >&2; exit 64; }

OPT_JSON=0; OPT_IDLE=20; OPT_CODE_ROOT=""; OPT_MEGA_ROOT=""; OPT_NOW=""; OPT_BACKLOG=""; OPT_REPO=""
while [ $# -gt 0 ]; do
  case "$1" in
    --json) OPT_JSON=1; shift ;;
    --idle-min) [ $# -ge 2 ] || bad "--idle-min needs a value"; OPT_IDLE="$2"; shift 2 ;;
    --code-root) [ $# -ge 2 ] || bad "--code-root needs a value"; OPT_CODE_ROOT="$2"; shift 2 ;;
    --megagoals-root) [ $# -ge 2 ] || bad "--megagoals-root needs a value"; OPT_MEGA_ROOT="$2"; shift 2 ;;
    --now) [ $# -ge 2 ] || bad "--now needs a value"; OPT_NOW="$2"; shift 2 ;;
    --backlog-file) [ $# -ge 2 ] || bad "--backlog-file needs a value"; OPT_BACKLOG="$2"; shift 2 ;;
    --repo-root) [ $# -ge 2 ] || bad "--repo-root needs a value"; OPT_REPO="$2"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) bad "unknown flag '$1' (see --help)" ;;
  esac
done
case "$OPT_IDLE" in ''|*[!0-9]*) bad "--idle-min must be a whole number of minutes" ;; esac
NOW="${OPT_NOW:-$(date +%s)}"
case "$NOW" in ''|*[!0-9]*) bad "--now must be epoch seconds" ;; esac

if [ -n "$OPT_REPO" ]; then REPO="$OPT_REPO"
elif [ -n "${REPO_ROOT:-}" ]; then REPO="$REPO_ROOT"
else REPO="$("$GIT_BIN" rev-parse --show-toplevel 2>/dev/null || pwd)"; fi
[ -d "$REPO" ] || bad "repo root '$REPO' is not a directory"
REPO="$(canon "$REPO")"
CODE_ROOT="$(canon "${OPT_CODE_ROOT:-$REPO}")"
MEGA_ROOT="${OPT_MEGA_ROOT:-$REPO/_meta/megagoals}"
BACKLOG="${OPT_BACKLOG:-$REPO/_meta/BACKLOG.md}"
[ -r "$BACKLOG" ] || { echo "board work: no readable backlog at $BACKLOG" >&2; exit 1; }
LEDGER_ROOT="$(kit_resolve_log_dir)" || exit 1
[ -d "$LEDGER_ROOT" ] && LEDGER_ROOT="$(canon "$LEDGER_ROOT")"

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ---- source readers: each writes normalized JSON under $T ----------------------------------

# src_board: id + leading status word per Active-queue row, via the one board row parser.
src_board() {
  ( . "$WORK_DIR/parse-board.sh" && pb_rows "$BACKLOG" ) | awk -F'\t' '{print $1 "\t" $2}' \
    | jq -Rn '[inputs | split("\t") | {item: .[0], lead: .[1]}]' > "$T/board.json"
}

# src_git <root> <name>: branches (with the runid-normalized slug) and worktrees (canonical path).
src_git() {
  local root="$1" name="$2" line p b
  "$GIT_BIN" -C "$root" for-each-ref --format='%(refname)' refs/heads 2>/dev/null | sed 's|^refs/heads/||' > "$T/$name.names"
  sed 's|^[^/]*/||' "$T/$name.names" | runid_lines > "$T/$name.norms"
  paste "$T/$name.names" "$T/$name.norms" | jq -Rn '[inputs | split("\t") | {name: .[0], norm: .[1]}]' > "$T/$name.branches"
  "$GIT_BIN" -C "$root" worktree list --porcelain 2>/dev/null | awk '
    /^worktree /{ if (p != "") print p "\t" b; p = substr($0, 10); b = "" }
    /^branch /{ b = substr($0, 8); sub("^refs/heads/", "", b) }
    END { if (p != "") print p "\t" b }' > "$T/$name.wtraw"
  : > "$T/$name.wtcanon"
  while IFS= read -r line; do
    p="${line%%$'\t'*}"; b="${line#*$'\t'}"
    printf '%s\t%s\n' "$(canon "$p")" "$b" >> "$T/$name.wtcanon"
  done < "$T/$name.wtraw"
  jq -Rn '[inputs | split("\t") | {path: .[0], branch: .[1]}]' < "$T/$name.wtcanon" > "$T/$name.wts"
  jq -n --slurpfile b "$T/$name.branches" --slurpfile w "$T/$name.wts" '{branches: $b[0], wts: $w[0]}' > "$T/$name.json"
}

# src_drafts: id -> slug from .claude/goals/{,done/} of the repo root and every worktree of it.
src_drafts() {
  local p d f files=()
  while IFS= read -r p; do
    for d in goals goals/done; do
      for f in "$p/.claude/$d/"*.md; do [ -f "$f" ] && files+=("$f"); done
    done
  done < <({ printf '%s\n' "$REPO"; cut -f1 "$T/main.wtcanon"; } | awk '!seen[$0]++')
  : > "$T/drafts.raw"
  if [ "${#files[@]}" -gt 0 ]; then
    awk '
      FNR == 1 { fm = 0; id = ""; slug = "" }
      /^---[ \t]*$/ { fm++; if (fm == 2) { if (id != "" && slug != "") print id "\t" slug; nextfile } next }
      fm == 1 && /^id:/ { id = $0; sub(/^id:[ \t]*/, "", id); gsub(/[ \t\r]+$/, "", id) }
      fm == 1 && /^slug:/ { slug = $0; sub(/^slug:[ \t]*/, "", slug); gsub(/[ \t\r]+$/, "", slug) }
    ' "${files[@]}" > "$T/drafts.raw"
  fi
  cut -f2 "$T/drafts.raw" | runid_lines > "$T/drafts.norm"
  paste "$T/drafts.raw" "$T/drafts.norm" | jq -Rn '[inputs | split("\t") | {id: .[0], slug: .[1], norm: .[2]}]' > "$T/drafts.json"
}

# src_mega: one JSON line per unchecked roadmap sub-goal, with its goal file's first Branch token.
src_mega() {
  local rm mslug id gf branch
  : > "$T/mega.json"
  for rm in "$MEGA_ROOT"/*/ROADMAP.md; do
    [ -f "$rm" ] || continue
    mslug="$(basename "$(dirname "$rm")")"
    while IFS= read -r id; do
      [ -n "$id" ] || continue
      gf=""
      case "$id" in
        SG-*) for f in "$MEGA_ROOT/$mslug/goals/${id#SG-}-"*.md; do [ -f "$f" ] && { gf="$f"; break; }; done ;;
        *) [ -f "$MEGA_ROOT/$mslug/goals/$id.md" ] && gf="$MEGA_ROOT/$mslug/goals/$id.md" ;;
      esac
      branch=""
      [ -n "$gf" ] && branch="$(grep -m1 -E '^\*\*Branch:\*\* ' "$gf" 2>/dev/null | sed -E 's/^\*\*Branch:\*\* *//' | awk '{print $1}')"
      jq -cn --arg item "$mslug/$id" --arg b "$branch" '{item: $item, branch: (if $b == "" then null else $b end)}' >> "$T/mega.json"
    done < <(awk 'match($0, /^- \[ \] (SG-[0-9]+|[0-9]+-[A-Za-z0-9_-]+)/) { print substr($0, 7, RLENGTH - 6) }' "$rm")
  done
}

# src_orca: one `worktree ps` call. orca is ok, absent (no binary) or error (exit, non-JSON, wrong shape).
src_orca() {
  local out state=ok
  if ! command -v "$ORCA_BIN" >/dev/null 2>&1; then state=absent
  elif ! out="$("$ORCA_BIN" worktree ps --json --limit 500 2>/dev/null)"; then state=error
  elif ! printf '%s' "$out" | jq -e '(.result.worktrees | type == "array") and all(.result.worktrees[]; (.path | type) == "string")' >/dev/null 2>&1; then state=error
  fi
  if [ "$state" != ok ]; then
    printf '{"orca":"%s","truncated":false,"rows":[]}\n' "$state" > "$T/orca.json"; return 0
  fi
  local pm="$T/orca.pathmap" p
  printf '%s' "$out" | jq -r '.result.worktrees[].path' | while IFS= read -r p; do
    printf '%s\t%s\n' "$p" "$(canon "$p")"
  done | jq -Rn '[inputs | split("\t") | {(.[0]): .[1]}] | add // {}' > "$pm"
  printf '%s' "$out" | jq --slurpfile pm "$pm" '
    {orca: "ok",
     truncated: (.result.truncated == true),
     rows: [.result.worktrees[] | {
       cpath: ($pm[0][.path] // .path),
       branch: ((.branch // "") | sub("^refs/heads/"; "")),
       hostId: (.hostId // "local"),
       status: .status,
       live: .liveTerminalCount,
       last: .lastOutputAt,
       working: any(.agents[]?; .state == "working")}]}' > "$T/orca.json"
}

# src_ledger: `<rid>\t<phase>` per `GATE | <phase> | ran` line across runs/*.log, phase normalized
# the way gate-ledger.sh normalize_phase does (execute -> build, battery -> review).
src_ledger() {
  local logs=("$LEDGER_ROOT/runs/"*.log)
  : > "$T/ledger.raw"
  if [ -e "${logs[0]}" ]; then
    awk -F' \\| ' '
      $2 == "GATE" {
        r = $4; gsub(/^[ \t]+|[ \t\r]+$/, "", r); if (r != "ran") next
        p = tolower($3); gsub(/\([^)]*\)/, "", p); gsub(/^[ \t]+|[ \t]+$/, "", p); gsub(/[ \t]+/, "-", p)
        if (p == "execute") p = "build"; if (p == "battery") p = "review"
        s = FILENAME; sub(/^.*\//, "", s); sub(/\.log$/, "", s)
        print s "\t" p
      }' "${logs[@]}" > "$T/ledger.raw"
  fi
  jq -Rn 'reduce inputs as $l ({}; ($l | split("\t")) as $p | .[$p[0]] += [$p[1]])' < "$T/ledger.raw" > "$T/ledger.json"
}

src_board
src_git "$REPO" main
if [ "$CODE_ROOT" = "$REPO" ]; then cp "$T/main.json" "$T/code.json"; else src_git "$CODE_ROOT" code; fi
src_drafts
src_mega
src_orca
src_ledger

# ---- join, flags, sort ---------------------------------------------------------------------

JOIN='
def unk: {state: "unknown", idle_s: null, reasons: []};
def by_norm($g; $n): if $n == "" then [] else [$g.branches[] | select(.norm == $n)] end;
def wt_of($g; $b): ([$g.wts[] | select(.branch == $b)] | .[0].path) // null;
def rung_of($ph):
  if any($ph[]; . == "ship") then "shipped" elif any($ph[]; . == "review") then "reviewed"
  elif any($ph[]; . == "build") then "built" elif any($ph[]; . == "validate") then "validated" else "none" end;
def agent_of($o; $wt; $br):
  if $o.orca != "ok" then {state: "unknown", idle_s: null, reasons: ["no-orca"]}
  else
    (([$o.rows[] | select(.cpath == $wt)] | .[0]) // ([$o.rows[] | select(.branch == $br)] | .[0])) as $r
    | if $r == null then {state: "unknown", idle_s: null, reasons: ["not-in-orca"]}
      elif $r.hostId != "local" then {state: "unknown", idle_s: null, reasons: ["no-orca"]}
      elif ($r.status | IN("working", "inactive")) | not then {state: "unknown", idle_s: null, reasons: ["no-terminal"]}
      elif $r.status == "working" or $r.working then {state: "working", idle_s: null, reasons: []}
      elif ($r.live // 0) > 0 and ($r.last | type) == "number"
        then {state: "idle", idle_s: ([0, (($now * 1000 - $r.last) / 1000 | floor)] | max), reasons: []}
      else {state: "unknown", idle_s: null, reasons: ["no-terminal"]}
      end
  end;
def rec($origin; $item; $branch; $wt; $ag; $reasons; $ph; $inprog; $dus):
  ($reasons | unique) as $rs
  | {item: $item, origin: $origin, branch: $branch, worktree: $wt,
     agent: {state: $ag.state, idle_s: $ag.idle_s},
     rung: rung_of($ph),
     flags: ([(if $inprog and $ag.state == "idle" and $ag.idle_s >= $idle_min * 60 then "PARKED" else empty end),
              (if $dus and any($ph[]; . == "ship") then "DONE-UNSEEN" else empty end),
              (if ($rs | length) > 0 then "INDETERMINATE" else empty end)] | sort),
     reasons: $rs};
def joined($g; $b; $origin; $item; $inprog; $dus; $extra):
  wt_of($g; $b.name) as $wt
  | (if $wt == null then {state: "unknown", idle_s: null, reasons: (if $inprog then ["no-worktree"] else [] end)}
     else agent_of($orca[0]; $wt; $b.name) end) as $ag
  | rec($origin; $item; $b.name; $wt; $ag; $ag.reasons + $extra; ($ledger[0][$b.norm] // []); $inprog; $dus);

($board[0] | map(.item) | group_by(.) | map({key: .[0], value: length}) | from_entries) as $cnt
| [ $board[0][] | select(.lead | IN("claimed", "speccing", "validated", "executing", "shipped")) ] | unique_by(.item)
| map(. as $c
    | ($c.lead == "shipped") as $shipped
    | (if $cnt[$c.item] > 1 then ["duplicate-id"] else [] end) as $dup
    | ((first($drafts[0][] | select(.id == $c.item))) // null) as $d
    | (if $d == null then {br: null, why: "no-draft"}
       else by_norm($gmain[0]; $d.norm) as $bs
         | if ($bs | length) == 0 then {br: null, why: "no-branch"}
           elif ($bs | length) > 1 then {br: null, why: "ambiguous"}
           else {br: $bs[0], why: null} end
       end) as $r
    | if $r.br == null then
        if $shipped and $r.why != "ambiguous" then {unchecked: 1}
        else rec("board"; $c.item; null; null; unk; [$r.why] + $dup; []; ($shipped | not); false) end
      else joined($gmain[0]; $r.br; "board"; $c.item; ($shipped | not); true; $dup) end) as $bi
| [ $mega[] | . as $m
    | if $m.branch == null then rec("mega"; $m.item; null; null; unk; ["no-branch"]; []; true; false)
      else (([$gcode[0].branches[] | select(.name == $m.branch)] | .[0]) // null) as $b
        | if $b == null then empty else joined($gcode[0]; $b; "mega"; $m.item; true; false; []) end
      end ] as $mi
| {schema: 1, generated_at: $now, idle_min: $idle_min, repo_root: $repo, ledger_root: $lroot,
   orca: $orca[0].orca, truncated: $orca[0].truncated,
   unchecked_shipped: ($bi | map(select(.unchecked)) | length),
   items: (($bi | map(select(.unchecked | not))) + $mi | sort_by([(.flags | length == 0), .item]))}
'

RESULT="$(jq -n \
  --slurpfile board "$T/board.json" --slurpfile drafts "$T/drafts.json" \
  --slurpfile gmain "$T/main.json" --slurpfile gcode "$T/code.json" \
  --slurpfile orca "$T/orca.json" --slurpfile mega "$T/mega.json" --slurpfile ledger "$T/ledger.json" \
  --argjson now "$NOW" --argjson idle_min "$OPT_IDLE" --arg repo "$REPO" --arg lroot "$LEDGER_ROOT" \
  "$JOIN")" || { echo "board work: join failed" >&2; exit 1; }

if [ "$OPT_JSON" = 1 ]; then printf '%s\n' "$RESULT"; exit 0; fi

# ---- table ---------------------------------------------------------------------------------

printf '%s\n' "$RESULT" | jq -r '
  ["ITEM", "WORKTREE", "AGENT", "RUNG", "FLAGS"],
  (.items[] | . as $i | [
    .item,
    ((.worktree // "-") | split("/") | last),
    (if .agent.state == "idle" then "idle \(.agent.idle_s / 60 | floor)m" else .agent.state end),
    .rung,
    (if (.flags | length) == 0 then "-"
     else [.flags[] | if . == "INDETERMINATE" then "INDETERMINATE(\($i.reasons | join(",")))" else . end] | join(" ") end)
  ]) | @tsv' | awk -F'\t' '
    { for (i = 1; i <= NF; i++) { c[NR, i] = $i; if (length($i) > w[i]) w[i] = length($i) }; n = NR; nf = NF }
    END { for (r = 1; r <= n; r++) { line = ""
            for (i = 1; i <= nf; i++) line = line (i < nf ? sprintf("%-" w[i] "s  ", c[r, i]) : c[r, i])
            print line } }'

printf '%s\n' "$RESULT" | jq -r '
  "",
  "idle threshold: \(.idle_min) min (PARKED needs an in-progress row idle at least that long)",
  "orca: \(.orca) (scope: local worktrees, worktree ps limit 500\(if .truncated then ", TRUNCATED page: rows past it read as not-in-orca" else "" end))",
  "ledger: \(.ledger_root)",
  "legend: shipped = the ledger holds a ship record (written before the PR merges); unknown = a key is missing, never idle or done; DONE-UNSEEN = shipped but branch or worktree still alive",
  (if .unchecked_shipped > 0 then "\(.unchecked_shipped) shipped rows unchecked (no draft or no branch to join)" else empty end)'
